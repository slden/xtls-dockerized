#!/bin/bash
DEST_PATH="TEST"

Precheck() {
	DOCKER_V=$(docker -v | grep -i "version")
	DOCKER_COMPOSE_V=$(docker-compose -v | grep -i "version")
	if [ -z "$DOCKER_V" ] || [ -z "$DOCKER_COMPOSE_V" ]; then
		echo "Docker or docker-compose not found. ";
		exit 0
	fi
	case "${1}" in
	1)
		if [ -e tls ]; then
			# if body
			rm -rf tls
		fi
		;;
	*) ;;
	esac

	EssentialFiles="Caddyfile .settings xray/config.json docker-compose.yml"
	for file in $EssentialFiles; do
		if [ ! -e $file ]; then
			case "${file}" in
			"Caddyfile" | "xray/config.json" | "docker-compose.yml")
				mkdir -p "$(dirname "$file")"
				curl -fsSL "https://raw.githubusercontent.com/slden/xtls-dockerized/main/${file}" -o "$file"
				;;
			".settings")
				touch $file
				;;
			*) ;;
			esac
		fi
	done

	curl -fsSL "https://raw.githubusercontent.com/slden/xtls-dockerized/main/decoy-website.tar.gz" -o ./decoy-website.tar.gz
	mkdir site
	tar -zxf ./decoy-website.tar.gz -C site
	mv site/decoy-website/* site/

	# qrc is used to generate QR codes out of connection links
	ARCH=$(uname -m | grep -i "x86_64")
	if [ -z $ARCH ]; then
		curl -Ls "https://github.com/fumiyas/qrc/releases/download/v0.1.1/qrc_linux_arm" -o ./qrc
	else
		curl -Ls  "https://github.com/fumiyas/qrc/releases/download/v0.1.1/qrc_linux_amd64" -o ./qrc
	fi

	chmod +x ./qrc
}

ChangeSettings() {
	if [ -z "$(grep "$1" ./.settings)" ]; then
		echo "$1=$2" >>./.settings
	else
		sed -i -E "s|$1=.+|$1=$2|g" ./.settings
	fi
}


SetCaddy() {
  count=1
  domains=""

  echo -e "Please input your domain(s). \nYes you can enter more than one domain!"
  while read -p "Domain #$count: (hit enter to skip):   " input; do
    if [ "$input" = "" ]; then break; fi

    if [ "$count" -eq 1 ]; then
      domains="$input"
    else
      domains="$domains, $input"
    fi

    count=$((count+1))

    # echo "Added $input to your list of domain, add another one and hit enter, or if you're finished just press enter" >&2
    echo "Domains: $domains"
  done
	
  sed -i -E "1s|.*\{|$domains \{|g" ./Caddyfile
  echo -e "\nFallback to use \n\t1.file_server for a decoy website \n\t2.redirect to another URL?\n(Default 1) : "
	read mode
	case "${mode}" in
	2)
		echo "Using redirect to another URL"
		read -p "Please input the URL (e.g. https://google.com) you want to redirect to as fallback: " ppppp
		sed -i -E "14,+0s|^\s+#+| |g" ./Caddyfile
		sed -i -E "11,+1s|^|#|g" ./Caddyfile
		sed -i -E "14s|redir .*|redir $ppppp {|g" ./Caddyfile
		;;
	*)
		echo "Using file_server to serve a decoy website"
		sed -i -E "14,+0s|^| #|g" ./Caddyfile
		sed -i -E "11,+1s|^\s+#+| |g" ./Caddyfile
		;;
	esac
	ChangeSettings "DOMAINS" "$domains"
}


ChangeCaddy() {
	iscaddyset=$(grep 'DOMAINS' ./.settings | awk '{print NR}' | sed -n '$p')
	case "${iscaddyset}" in
	1)
		read -p "Want to change domain settings? (yN default N): " changefqdn
		case "${changefqdn}" in
		'y' | 'Y')
			SetCaddy
			;;
		*) ;;
		esac
		;;
	*)
		SetCaddy
		;;
	esac
}

ChangeUUID() {
	case "$(grep 'UUID' ./.settings | awk '{print NR}' | sed -n '$p')" in
	1)
		read -p "Change the UUID? (y or N def N)" setUUID
		case "${setUUID}" in
		'y' | 'Y')
			UUIDN1=$(curl -s https://www.uuidgenerator.net/api/version4)
			sed -i -E "s|\w{8}(-\w{4}){3}-\w{12}\"|$UUIDN1\"|g" ./xray/config.json
			ChangeSettings "UUID" "$UUIDN1"
			;;
		*) ;;
		esac
		;;
	*)
		UUIDN1=$(curl -s https://www.uuidgenerator.net/api/version4)
		sed -i -E "s|\w{8}(-\w{4}){3}-\w{12}\"|$UUIDN1\"|g" ./xray/config.json
		ChangeSettings "UUID" "$UUIDN1"
		echo -e "Changed the UUID in configs to a random one: \n\t\"$UUIDN1\""

		echo -e "Generating random paths for vmess and vless protocols..."
		vless_ws_path=$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-15} | head -n 1)
		vmess_tcp_path=$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-15} | head -n 1)
		vmess_ws_path=$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-15} | head -n 1)
		ChangeSettings "vless_ws_path" "$vless_ws_path"
		ChangeSettings "vmess_tcp_path" "$vmess_tcp_path"
		ChangeSettings "vmess_ws_path" "$vmess_ws_path"

		echo "Vless WS path: /$vless_ws_path"
		echo "Vmess TCP path: /$vmess_tcp_path"
		echo "Vless WS path: /$vmess_ws_path"

		sed -i -E "s|/vless-ws-path\"|/$vless_ws_path\"|g" ./xray/config.json
		sed -i -E "s|/vmess-tcp-path\"|/$vmess_tcp_path\"|g" ./xray/config.json
		sed -i -E "s|/vmess-ws-path\"|/$vmess_ws_path\"|g" ./xray/config.json

		;;
	esac
}

ChangeFlow() {
	# Xray 1.8+ rejects xtls-rprx-direct/origin/splice.
	# TLS is terminated by Caddy; the published links are VLESS/VMESS over WS and do not use flow.
	sed -i '/"flow":/d' xray/config.json
	ChangeSettings "FLOW" ""
}

ExposeSettingsValues() {
	DOMAINS=$(grep 'DOMAINS' .settings | awk -F= '{print $2}')
	UUID=$(grep 'UUID' .settings | awk -F= '{print $2}')
	FLOW=$(grep 'FLOW' .settings | awk -F= '{print $2}')
	vless_ws_path=$(grep 'vless_ws_path' .settings | awk -F= '{print $2}')
	vmess_tcp_path=$(grep 'vmess_tcp_path' .settings | awk -F= '{print $2}')
	vmess_ws_path=$(grep 'vmess_ws_path' .settings | awk -F= '{print $2}')
}

GenerateVlessWSLink() {
	host_domain=$1
	vless_share="vless://$UUID@$host_domain:443?encryption=none&security=tls&type=ws&path=%2F$vless_ws_path&sni=$host_domain&host=$host_domain#vless-$host_domain"
}

GenerateVmessWSLink() {
	host_domain=$1
	json_part="{\"add\":\"$host_domain\",\"aid\":\"0\",\"alpn\":\"\",\"host\":\"\",\"id\":\"$UUID\",\"net\":\"ws\",\"path\":\"/$vmess_ws_path\",\"port\":\"443\",\"ps\":\"vmess-$host_domain\",\"scy\":\"none\",\"sni\":\"\",\"tls\":\"tls\",\"type\":\"\",\"v\":\"2\"}"
	vmess_ws_share="vmess://$(echo -n $json_part | base64 -w 0 | sed -E 's/=//g')"
}

ShowLink() {
	ExposeSettingsValues

	echo -e "\n\n********************\n\n"

	for domain in ${DOMAINS//,/ }
	do
		echo -e "Links for domain \"$domain\""

		# vless_share="vless://$UUID@$domain:443?encryption=none&security=tls&type=ws&path=%2F$vless_ws_path&sni=$domain&host=$domain#vless-$domain"
		GenerateVlessWSLink $domain

		echo -e "\n*** VLESS over WS: ***"
		echo "$vless_share"

		GenerateVmessWSLink $domain
		echo -e "\n*** VMESS over WS: ***"
		echo -e $vmess_ws_share


		echo -e "\n\n********************\n\n"
	done
}

QR() {
	ExposeSettingsValues
	IFS=', ' read -r -a array <<< "$DOMAINS"
	

	if [ ${#array[@]} == "1" ]
	then
		selectedIndex="0"
	else 
		echo "Select the domain you want to print QR codes for:"

		for index in "${!array[@]}"
		do
				echo "$index) ${array[index]}"
		done
		read -p "Enter a number between 0 and $((${#array[@]}-1)): " selectedIndex
	fi

	if [ $selectedIndex -gt ${#array[@]} ] || [ $selectedIndex -lt 0 ]
	then
		echo -e "\nYou entered a wrong number! Try Again!\n"
		sleep 0.5
		QR
	else
		echo -e "QR codes for domain \"${array[$selectedIndex]}\""
		selectedDomain=${array[$selectedIndex]}
		GenerateVlessWSLink $selectedDomain
		GenerateVmessWSLink $selectedDomain

		echo -e "\n\nVLESS QR Code: \n"
		./qrc "$vless_share"
		echo -e "\n\nVMESS QR Code: \n"
		./qrc "$vmess_ws_share"
	fi
}

Update() {
	Precheck 2
	imageID=$(docker-compose images | grep $1 | awk '{print $4}')
	if [ -z $imageID ]; then
		echo "no running container found"
		exit 0
	fi
	case "${1}" in
	"caddy" | "xray")
		#docker-compose stop $1
		docker-compose rm -s $1
		docker rmi $imageID
		docker-compose up -d $1
		;;
	"acme")
		echo "Emmmm"
		;;
	*)
		echo "default (none of caddy, xray or acme)"
		;;
	esac
}

Install() {
	Precheck 1
	ChangeCaddy
	ChangeUUID
	ChangeFlow
	docker-compose down
	docker-compose up -d

	sed -i.old '/^.*restart xray.*/d' /var/spool/cron/crontabs/"$(whoami)"
	if [ -e "/usr/bin/docker-compose" ]; then
		DockerComposePath="/usr/bin/docker-compose"
		echo "0 0 * * * cd $PWD && $DockerComposePath restart xray" >>/var/spool/cron/crontabs/"$(whoami)"
	elif [ -e "/usr/local/bin/docker-compose" ]; then
		DockerComposePath="/usr/local/bin/docker-compose"
		echo "0 0 * * * cd $PWD && $DockerComposePath restart xray" >>/var/spool/cron/crontabs/"$(whoami)"
	fi

	ShowLink
}

Remove() {
	Precheck 3
	sed -i '/caddy-xtls/d' /var/spool/cron/crontabs/"$(whoami)"
	docker-compose down --rmi all
}

main() {
	case "${1}" in
	"install")
		Install
		;;
	"update")
		Update $2
		;;
	"remove")
		Remove
		;;
	"links")
		ShowLink
		;;
	"qr")
		QR

	;;
	*)
    echo "Usage guide:"
    echo -e "./install.sh install\t\t# Step-By-Step configuration and installation"
    echo -e "./install.sh remove \t\t# Removes the docker containers"
    echo -e "./install.sh links \t\t# Prints the ready to use links to connect to server" 
		echo -e "./install.sh qr \t\t# Generates QR codes to scan directly with your phone" 
		;;
	esac

}

main $1 $2