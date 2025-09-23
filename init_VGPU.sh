#!/bin/sh


#Making sure this script runs with elevated privileges
if [ $(id -u) -ne 0 ]
	then
		echo "Please run this as root!" 
		exit 1
fi


GPU=
MAX=0
UUID=\"`uuidgen`\"
VIRT_USER=`logname`

#Finding the Intel GPU and choosing the one with highest weight value
for i in $(find /sys/devices/pci* -name 'mdev_supported_types'); do
for y in $(find $i -name 'description'); do
WEIGHT=`cat $y | tail -1 | cut -d ' ' -f 2`
if [ $WEIGHT -gt $MAX ]; then
GPU=`echo $y | cut -d '/' -f 1-7`

#Saving the uuid for future optional verification by the user
echo "ls $GPU/devices" > check_gpu.sh
chmod +x check_gpu.sh
chown $VIRT_USER check_gpu.sh

fi
done

done


#echo "	<hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='off'>" > virsh.txt
#echo "	<source>" >> virsh.txt

#echo "	<address uuid=$UUID/>" >> virsh.txt
#echo "</source>" >> virsh.txt
#echo "</hostdev>" >> virsh.txt



#Initializing virtual GPU on every startup
echo "echo $UUID > $GPU/create" >> gvt_pe.sh

#Create a systemd service to initialize the GPU on startup
cp gvt_pe.service /etc/systemd/system/gvt_pe.service
chmod 644 /etc/systemd/system/gvt_pe.service

mv gvt_pe.sh /usr/bin/gvt_pe.sh

systemctl enable gvt_pe.service

systemctl start gvt_pe.service

chown $VIRT_USER virsh.txt


