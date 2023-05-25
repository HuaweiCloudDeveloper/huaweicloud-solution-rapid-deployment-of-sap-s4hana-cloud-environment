#!/bin/sh -x
HANA_BUSINESSIP_1=${1}
HANA_BUSINESSIP_2=${2}
S4_BUSINESSIP_1=${3}
S4_BUSINESSIP_2=${4}
SFS_TURBO_S4_SAPMNT=${5}
SFS_TURBO_S4_TRANS=${6}
SAP_S4_NAME=${7}
SAP_HANA_NAME=${8}
SID=${9}
ASCS_INSTANCE_NUMBE=${10}
ERS_INSTANCE_NUMBE=${11}
# shellcheck disable=SC2163
export ${12}
# shellcheck disable=SC2163
export ${13}
OBS_BUCKET_NAME=${14}
#hosts and fstab configurations
if  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP_1}" ] ||  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP_2}"  ]
then
    while :
    do  
      sleep 5
      if lsblk|grep -q  "vdg"
      then
        break
      fi  
    done
    echo "${HANA_BUSINESSIP_1}     ${SAP_HANA_NAME}-1     ${SAP_HANA_NAME}" >> /etc/hosts
    echo "${HANA_BUSINESSIP_2}     ${SAP_HANA_NAME}-2" >> /etc/hosts
    mkdir -p /usr/sap /hana/log /hana/shared /hana/data
    mkswap /dev/vdb
    swapon /dev/vdb
    mkfs.xfs /dev/vdc
    mkfs.xfs /dev/vdd
    mkfs.xfs /dev/vde 
    pvcreate /dev/vdf /dev/vdg
    vgcreate vghana /dev/vdf /dev/vdg
    lvcreate -i 2 -l 100%VG -n lvhanadata vghana
    mkfs.xfs /dev/mapper/vghana-lvhanadata
    {
        echo "$(blkid /dev/vdb|awk '{print $2}') swap swap defaults 0 0"
        echo "$(blkid /dev/vdc|awk '{print $2}') /usr/sap xfs defaults 0 0"
        echo "$(blkid /dev/vdd|awk '{print $2}') /hana/log xfs defaults 0 0"
        echo "$(blkid /dev/vde|awk '{print $2}') /hana/shared xfs defaults 0 0"
        echo "$(blkid /dev/mapper/vghana-lvhanadata|awk '{print $2}') /hana/data xfs defaults 0 0" 
    } >> /etc/fstab
    mount -a
elif [ "$(hostname -I|awk '{print $1}')" = "${S4_BUSINESSIP_1}"  ] ||  [ "$(hostname -I|awk '{print $1}')" = "${S4_BUSINESSIP_2}"  ]
then
    while :
    do  
      sleep 5
      if lsblk|grep -q  "vdc" && lsblk|grep -q  "sdc"
      then
        break
      fi  
    done
    {
        echo "${S4_BUSINESSIP_1}     ${SAP_S4_NAME}-1"
        echo "${S4_BUSINESSIP_2}     ${SAP_S4_NAME}-2"
        echo "${S4_BUSINESSIP_1}     ascsha"
        echo "${S4_BUSINESSIP_2}     ersha"
        echo "${HANA_BUSINESSIP_1}     ${SAP_HANA_NAME}"
    } >> /etc/hosts
    mkdir -p  /sapmnt/ /usr/sap/
    mkswap /dev/vdb
    swapon /dev/vdb
    mkfs.xfs /dev/vdc
    {
         echo "$(blkid /dev/vdb|awk '{print $2}') swap swap defaults 0 0" 
         echo "$(blkid /dev/vdc|awk '{print $2}') /usr/sap xfs defaults 0 0"
    } >> /etc/fstab
    mount -a
    mkdir -p /usr/sap/trans/
    {
         echo "${SFS_TURBO_S4_SAPMNT} /sapmnt nfs vers=3,timeo=600,nolock 1 2"
         echo "${SFS_TURBO_S4_TRANS} /usr/sap/trans nfs vers=3,timeo=600,nolock 1 2"
    } >> /etc/fstab
    mount -a
    if [ "$(hostname -I|awk '{print $1}')" = "${S4_BUSINESSIP_1}"  ];then
       mkfs.xfs /dev/sdb
       mkdir -p /usr/sap/${SID}/ASCS${ASCS_INSTANCE_NUMBE}
       mount /dev/sdb /usr/sap/${SID}/ASCS${ASCS_INSTANCE_NUMBE} 
    else
       mkfs.xfs /dev/sdc
       mkdir -p /usr/sap/${SID}/ERS${ERS_INSTANCE_NUMBE}
       mount /dev/sdc /usr/sap/${SID}/ERS${ERS_INSTANCE_NUMBE}
    fi
fi
sed -i 's/\(^127.0.0.1\).*\('${SAP_S4_NAME}'.*\|'${SAP_HANA_NAME}'.*\).*/#\1    \2/' /etc/hosts
sed -i 's/\(manage_etc_hosts: localhost\)/#\1/' /etc/cloud/cloud.cfg

#obs configurations
if  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP_1}" ] ||  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP_2}"  ] && [ "${OBS_BUCKET_NAME}" != "null" ]
then
    az=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
    azaz=${az::-1}
    echo ${AK}:${SK} > /etc/passwd-obsfs
    chmod 600 /etc/passwd-obsfs
    mkdir -p /hana/backup
    if [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP_1}"  ];then
       export obs_backup=${OBS_BUCKET_NAME,,}-backup-1
    else
       export obs_backup=${OBS_BUCKET_NAME,,}-backup-2
    fi
    cat > /etc/init.d/obsfs <<- EOF
#!/bin/bash
obsfs $obs_backup /hana/backup -o url=obs.$azaz.myhuaweicloud.com -o passwd_file=/etc/passwd-obsfs -o big_writes -o max_write=131072 -o max_background=100 -o use_ino -o allow_other -o nonempty
EOF
    chmod +x /etc/init.d/obsfs
    if which obsfs;then
      systemctl daemon-reload
      systemctl start obsfs.service
      chkconfig obsfs on
    else
       echo "obsfs uninstalled"
    fi
    
fi
