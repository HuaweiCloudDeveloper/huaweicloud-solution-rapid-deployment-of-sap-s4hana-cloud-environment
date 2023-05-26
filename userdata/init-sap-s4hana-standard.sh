#!/bin/sh -x
HANA_BUSINESSIP=${1}
SFS_TURBO_S4_TRANS=${2}
# shellcheck disable=SC2163
export ${3}
# shellcheck disable=SC2163
export ${4}
OBS_BUCKET_NAME=${5}
#hosts and fstab configurations
if  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP}" ]
then
    while :
    do  
      sleep 5
      if lsblk|grep -q  "vdg"
      then
        break
      fi  
    done
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
else
    while :
    do  
      sleep 5
      if lsblk|grep -q  "vdd"
      then
        break
      fi  
    done
    mkdir -p  /sapmnt/ /usr/sap/
    mkswap /dev/vdb
    swapon /dev/vdb
    mkfs.xfs /dev/vdc
    mkfs.xfs /dev/vdd
    {
         echo "$(blkid /dev/vdb|awk '{print $2}') swap swap defaults 0 0" 
         echo "$(blkid /dev/vdc|awk '{print $2}') /usr/sap xfs defaults 0 0"
         echo "$(blkid /dev/vdd|awk '{print $2}') /sapmnt xfs defaults 0 0"
    } >> /etc/fstab
    mount -a
    mkdir -p /usr/sap/trans/
    {
         echo "${SFS_TURBO_S4_TRANS} /usr/sap/trans nfs vers=3,timeo=600,nolock 1 2"
    } >> /etc/fstab
    mount -a
fi

#obs configurations
if  [ "$(hostname -I|awk '{print $1}')" = "${HANA_BUSINESSIP}" ]  && [ "${OBS_BUCKET_NAME}" != "null" ]
then
    az=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
    azaz=${az::-1}
    echo ${AK}:${SK} > /etc/passwd-obsfs
    chmod 600 /etc/passwd-obsfs
    mkdir -p /hana/backup
    export obs_backup=${OBS_BUCKET_NAME,,}-backup
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