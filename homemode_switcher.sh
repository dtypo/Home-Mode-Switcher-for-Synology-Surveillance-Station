#!/bin/bash

########## Mandatory configuration
SYNO_USER="user";
SYNO_PASS="password";
SYNO_URL="192.168.1.111:port";
########## 2FA configuration (optional)
SYNO_SECRET_KEY="";
PYTHON_VOLUME="volume1"
BLACKLISTED_IPS_OR_MACS="a0:b1:c2:d3:e4:f5 a1:b2:c3:d4:e5:f6 192.168.1.255"
######################################
######################################
######################################
######################################
######################################
######################################

ARGUMENTS=$@
MACS=$(echo $ARGUMENTS | tr '[:upper:]' '[:lower:]');
BLACKLIST=$(echo $BLACKLISTED_IPS_OR_MACS | tr '[:upper:]' '[:lower:]');

ID="$RANDOM";
COOKIESFILE="$0_cookies_$ID";
AMIHOME="$0_AMIHOME";

function totp_calculator() {
	test_python="/$PYTHON_VOLUME/@appstore/py3k/usr/local/bin/python3"
	test_pip="/$PYTHON_VOLUME/@appstore/py3k/usr/local/bin/pip"
	test_pyotp="/$PYTHON_VOLUME/@appstore/py3k/usr/local/lib/python3.8/site-packages/pyotp"
	if [ -f "$test_python" ]; then
		if [ -f "$test_pip" ]; then
			if [ -d "$test_pyotp" ]; then
				SYNO_OTP="$(python3 - <<END
import pyotp
totp = pyotp.TOTP("$SYNO_SECRET_KEY")
print(totp.now())
END
)"			
			else
				echo "Pyotp module is not installed"
				echo "Try with \"python3 /$PYTHON_VOLUME/@appstore/py3k/usr/local/bin/pip install pyotp\""
				exit 1;
			fi
			
		else
			echo "Pip is not installed"
			echo "Try with \"wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py\" followed by \"sudo python3 /tmp/get-pip.py\""
			exit 1;
		fi
		
	else
		echo "Python3 is not installed"
		echo "Install it from the Package Center"
		exit 1;
	fi
}

function switchHomemode()
{
	if [ -z "$SYNO_SECRET_KEY" ]; then
		echo "No 2FA secret key detected"
		login_output=$(wget -q --keep-session-cookies --save-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/auth.cgi?api=SYNO.API.Auth&method=Login&version=3&account=${SYNO_USER}&passwd=${SYNO_PASS}&session=SurveillanceStation"|awk -F'[][{}]' '{ print $4 }'|awk -F':' '{ print $2 }');
	else
		echo "2FA secret key detected, I'm using it"
		totp_calculator
		login_output=$(wget -q --keep-session-cookies --save-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/auth.cgi?api=SYNO.API.Auth&method=Login&version=3&account=${SYNO_USER}&passwd=${SYNO_PASS}&otp_code=${SYNO_OTP}&session=SurveillanceStation"|awk -F'[][{}]' '{ print $4 }'|awk -F':' '{ print $2 }');
	fi
	if [ "$login_output" == "true" ]; then 
		echo "Login to Synology successfull";
		homestate_prev_syno=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api=SYNO.SurveillanceStation.HomeMode&version=1&method=GetInfo&need_mobiles=true"|awk -F',' '{ print $124 }'|awk -F':' '{ print $2 }');
		if [ "$homestate" == "true" ] && [ "$homestate_prev_syno" != "$homestate" ]; then
			echo "Synology is NOT in Homemode but you're at home... Let's fix it"
			switch_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api=SYNO.SurveillanceStation.HomeMode&version=1&method=Switch&on=true");
			if [ "$switch_output" = '{"success":true}' ]; then  
				echo "Homemode correctly activated"; 
				echo $homestate>$AMIHOME
			else
				echo "Something went wrong during the activation of Homemode"
				exit 1;
			fi	
		elif [ "$homestate" == "false" ] && [ "$homestate_prev_syno != $homestate" ]; then
			echo "Synology is in Homemode but you're NOT at home... Let's fix it"
			switch_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}//webapi/entry.cgi?api=SYNO.SurveillanceStation.HomeMode&version=1&method=Switch&on=false");
			if [ "$switch_output" = '{"success":true}' ]; then  
				echo "Homemode correctly deactivated"; 
				echo $homestate>$AMIHOME
			else
				echo "Something went wrong during the deactivation of Homemode"
				exit 1;
			fi	
		elif [ "$homestate" == "false" ] && [ "$homestate_prev_syno == $homestate" ]; then
			echo "Synology is NOT in Homemode and you're NOT at home...Fixing only the AMIHOME file";
			echo $homestate>$AMIHOME
		elif [ "$homestate" == "true" ] && [ "$homestate_prev_syno == $homestate" ]; then
			echo "Synology is in Homemode and you're at home...Fixing only the AMIHOME file";
			echo $homestate>$AMIHOME
		fi
		logout_output=$(wget -q --load-cookies $COOKIESFILE -O- "http://${SYNO_URL}/webapi/auth.cgi?api=SYNO.API.Auth&method=Logout&version=1");
		if [ "$logout_output" = '{"success":true}' ]; then echo "Logout to Synology successfull"; fi
	else
		echo "Login to Synology went wrong";
		exit 1;
	fi
	rm $COOKIESFILE;
}

function macs_check()
{	
	matching_macs=0
	arp_table=$(arp -a|awk -F'[ ()]' 'BEGIN{OFS="_"} {print $3,$6}')
	echo "Hosts found in your network:"
	for host in $arp_table; do
		host_ip=$(echo $host|awk -F'[_]' '{print $1}')
		host_mac=$(echo $host|awk -F'[_]' '{print $2}')
		if [ "$host_mac" != "<incomplete>" ] && [[ ! "$BLACKLIST" =~ "$host_mac" ]] && [[ ! "$BLACKLIST" =~ "$host_ip" ]]; then
			ping_failed=$(ping -i 0.1 -c 1 $host_ip|awk '/100% packet loss/{ print $0 }')
			if [ -z "$ping_failed" ]; then
				echo $host
				for authorized_mac in $MACS
				do
					if [ "$host_mac" == "$authorized_mac" ]; then
						let "matching_macs+=1"
						echo "One match between active MACs and authorized MACs found: $host_mac"
					fi
				done
			else
				echo "$host (but doesn't ping! so won't be considered)"
			fi
		fi
	done
}

#Check for the list of MAC addresses authorized to activate Homemode passed as script arguments
if [ $# -eq 0 ]; then
	echo "MAC address or addresses missing"
	exit 1;
fi

#Check for previous state stored in a file for avoiding continuous SynoAPI calls
if [ -f $AMIHOME ]; then
	homestate_prev_file=$(<$AMIHOME)
else
	echo "unknown">$AMIHOME
	homestate_prev_file=$(<$AMIHOME)
fi

echo "[Previous state]Am I home? ${homestate_prev}" 
echo "MACs authorized to activate Homemode: $MACS"

#Check for currently active MAC addresses and comparison with the provided authorized MACs
macs_check
echo "Total matches: $matching_macs"

if [ "$matching_macs" -eq "0" ]; then
	homestate="false"
elif [ "$matching_macs" -gt "0" ]; then
	homestate="true"
fi
echo "[Current state]Am I home? ${homestate}"

if [ $homestate_prev_file != $homestate ]; then
	switchHomemode
else
	echo "No changes made"
fi

exit 0;
