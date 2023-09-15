#!/bin/bash

########## Mandatory configuration
SYNO_USER="user";
SYNO_PASS="password";
SYNO_URL="192.168.1.111:port";
########## 2FA configuration (optional)
SYNO_SECRET_KEY="";
######################################
######################################
######################################
######################################
######################################
######################################

ARGUMENTS=$@;
MACS=$(echo $ARGUMENTS | tr '[:lower:]' '[:upper:]');

ID="$RANDOM";
COOKIESFILE="$0_cookies_$ID";
AMIHOME="$0_AMIHOME";


function totp_calculator() {
	test_pip="/usr/lib/python3.8/site-packages/pip";
	test_pyotp="/usr/lib/python3.8/site-packages/pyotp";
	if [ -d "$test_pip" ]; then
		if [ -d "$test_pyotp" ]; then
			SYNO_OTP="$(python3 - <<END
import pyotp
totp = pyotp.TOTP("$SYNO_SECRET_KEY")
print(totp.now())
END
)"			
		else
			echo "Pyotp module is not installed";
			exit 1;
		fi
	else
		echo "Pip is not installed";
		exit 1;
	fi
}


function switchHomemode()
{
	if [ -z "$SYNO_SECRET_KEY" ]; then
		echo -e "\nNo 2FA secret key detected"
		login_output=$(wget -q --keep-session-cookies --save-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/auth.cgi?api=SYNO.API.Auth&method=login&version=3&account=${SYNO_USER}&passwd=${SYNO_PASS}&session=SurveillanceStation");
	else
		echo -e "\n2FA secret key detected, I'm using it";
		totp_calculator;
		login_output=$(wget -q --keep-session-cookies --save-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/auth.cgi?api=SYNO.API.Auth&method=login&version=3&account=${SYNO_USER}&passwd=${SYNO_PASS}&otp_code=${SYNO_OTP}&session=SurveillanceStation");
	fi
	login_result=$(echo ${login_output##*,*,});
	if [ "$login_result" == "\"success\":true}" ]; then 
		echo "Login to Synology successfull";
		syno_api_query=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api="SYNO.SurveillanceStation.HomeMode"&version="1"&method="GetInfo"&need_mobiles=true");
		IFS=',';
		read -a strarr <<< "$syno_api_query";
		previous_homestate_from_syno=$(echo ${strarr[145]});
		if [ "$homestate" == "\"on\":true" ] && [ "$previous_homestate_from_syno" != "$homestate" ]; then
			echo "Synology is NOT in Homemode but you're at home... Let's fix it";
			syno_api_switch_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api=SYNO.SurveillanceStation.HomeMode&version=1&method=Switch&on=true");
			if [ "$syno_api_switch_output" == '{"success":true}' ]; then  
				echo "Homemode correctly activated"; 
				echo $homestate>$AMIHOME;
			else
				echo "Something went wrong during the activation of Homemode";
				exit 1;
			fi	
		elif [ "$homestate" == "\"on\":false" ] && [ "$previous_homestate_from_syno != $homestate" ]; then
			echo "Synology is in Homemode but you're NOT at home... Let's fix it";
			syno_api_switch_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api=SYNO.SurveillanceStation.HomeMode&version=1&method=Switch&on=false");
			if [ "$syno_api_switch_output" = '{"success":true}' ]; then  
				echo "Homemode correctly deactivated"; 
				echo $homestate>$AMIHOME;
			else
				echo "Something went wrong during the deactivation of Homemode";
				exit 1;
			fi	
		elif [ "$homestate" == "\"on\":false" ] && [ "$previous_homestate_from_syno == $homestate" ]; then
			echo "Synology is NOT in Homemode and you're NOT at home...Fixing only the AMIHOME file";
			echo $homestate>$AMIHOME;
		elif [ "$homestate" == "\"on\":true" ] && [ "$previous_homestate_from_syno == $homestate" ]; then
			echo "Synology is in Homemode and you're at home...Fixing only the AMIHOME file";
			echo $homestate>$AMIHOME;
		fi
		logout_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}/webapi/auth.cgi?api=SYNO.API.Auth&method=Logout&version=1");
		if [ "$logout_output" = '{"success":true}' ]; then echo "Logout to Synology successfull"; fi
		rm $COOKIESFILE;
	else
		echo "Login to Synology went wrong";
		rm $COOKIESFILE;
		exit 1;
	fi
}


function macs_check_v1()
{	
	matching_macs=0
	ip_pool=$(echo ${SYNO_URL%.*:*}.0/24);
	echo "Scanning hosts in the same network of the Synology NAS...";
	nmap_scan="";
	while [ -z "$nmap_scan" ];
	do
		nmap_scan=$(timeout 1m nmap -sn --disable-arp-ping $ip_pool|awk '/MAC/{print $3}');
	done
	echo -e "\nHosts found in your network:";
	for host in $nmap_scan; do
		echo -e "\n$host";
		for authorized_mac in $MACS
		do
			if [ "$host" == "$authorized_mac" ]; then
				let "matching_macs+=1";
				echo -e "This MAC address matches with one of the authorized MAC addresses!";
			fi
		done
	done
	
}



#Check for the list of MAC addresses authorized to activate Homemode passed as script arguments
if [ $# -eq 0 ]; then
	echo "MAC address or addresses missing";
	exit 1;
fi

#Check for previous state stored in a file for avoiding continuous SynoAPI calls
if [ -f $AMIHOME ]; then
	previous_homestate_from_file=$(<$AMIHOME);
else
	echo "unknown">$AMIHOME
	previous_homestate_from_file=$(<$AMIHOME);
fi
echo -e "\n[Previous State] Am I home? $previous_homestate_from_file";
echo "MAC addresses authorized to enable the Homemode: $MACS";

#Check for currently active MAC addresses and comparison with the provided authorized MACs
macs_check_v1;

echo -e "\nTotal matches: $matching_macs";
if [ "$matching_macs" -eq "0" ]; then
	homestate="\"on\":false";
elif [ "$matching_macs" -gt "0" ]; then
	homestate="\"on\":true";
fi
echo "[Current State] Am I home? $homestate";
if [ $previous_homestate_from_file != $homestate ]; then
	echo "Switching Home Mode according to the [Current State]...";
	switchHomemode;
else
	echo "No changes made";
fi
exit 0;
