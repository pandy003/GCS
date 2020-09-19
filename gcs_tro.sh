#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
stty erase ^H

sh_ver='1.0.0'

green_font(){
	echo -e "\033[32m\033[01m$1\033[0m\033[37m\033[01m$2\033[0m"
}
red_font(){
	echo -e "\033[31m\033[01m$1\033[0m"
}
white_font(){
	echo -e "\033[37m\033[01m$1\033[0m"
}
yello_font(){
	echo -e "\033[33m\033[01m$1\033[0m"
}
Info=`green_font [資訊]` && Error=`red_font [錯誤]` && Tip=`yello_font [注意]`

[ $(id -u) != '0' ] && { echo -e "${Error}您必須以root用戶運行此腳本"; exit 1; }

######系統檢測元件######
check_sys(){
	#檢查系統
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	fi
	#檢查系統安裝命令
	if [[ ${release} == "centos" ]]; then
		PM='yum'
	else
		PM='apt'
	fi
}
#獲取IP
get_ip(){
	IP=$(curl -s ipinfo.io/ip)
	[ -z ${IP} ] && IP=$(curl -s http://api.ipify.org)
	[ -z ${IP} ] && IP=$(curl -s ipv4.icanhazip.com)
	[ -z ${IP} ] && IP=$(curl -s ipv6.icanhazip.com)
	[ ! -z ${IP} ] && echo ${IP} || echo
}
get_char(){
	SAVEDSTTY=`stty -g`
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2> /dev/null
	stty -raw
	stty echo
	stty $SAVEDSTTY
}
#防火牆配置
firewall_restart(){
	if [[ ${release} == 'centos' ]]; then
		if [[ ${version} -ge '7' ]]; then
			firewall-cmd --reload
		else
			service iptables save
			if [ -e /root/test/ipv6 ]; then
				service ip6tables save
			fi
		fi
	else
		iptables-save > /etc/iptables.up.rules
		if [ -e /root/test/ipv6 ]; then
			ip6tables-save > /etc/ip6tables.up.rules
		fi
	fi
	echo -e "${Info}防火牆設置完成！"
}
add_firewall(){
	if [[ ${release} == 'centos' &&  ${version} -ge '7' ]]; then
		if [[ -z $(firewall-cmd --zone=public --list-ports |grep -w ${port}/tcp) ]]; then
			firewall-cmd --zone=public --add-port=${port}/tcp --add-port=${port}/udp --permanent >/dev/null 2>&1
		fi
	else
		if [[ -z $(iptables -nvL INPUT |grep :|awk -F ':' '{print $2}' |grep -w ${port}) ]]; then
			iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
			iptables -I INPUT -p udp --dport ${port} -j ACCEPT
			iptables -I OUTPUT -p tcp --sport ${port} -j ACCEPT
			iptables -I OUTPUT -p udp --sport ${port} -j ACCEPT
			if [ -e /root/test/ipv6 ]; then
				ip6tables -I INPUT -p tcp --dport ${port} -j ACCEPT
				ip6tables -I INPUT -p udp --dport ${port} -j ACCEPT
				ip6tables -I OUTPUT -p tcp --sport ${port} -j ACCEPT
				ip6tables -I OUTPUT -p udp --sport ${port} -j ACCEPT
			fi
		fi
	fi
}

install_dir="$(pwd)/trojan"
install_trojan(){
	check_sys
	$PM -y install lsof jq curl
        # 取消 ↓
	#curl -s https://install.zerotier.com | sudo bash
	if [ ! -d $install_dir ]; then
                # 修改成GCP可用 ↓
		port=22
		until [[ -z $(lsof -i:${port}) ]]
		do
			port=$[${port}+1]
		done
		add_firewall
		firewall_restart
                # 修改成最新版本 ↓
		VERSION=1.16.0
		DOWNLOADURL="https://github.com/trojan-gfw/trojan/releases/download/v${VERSION}/trojan-${VERSION}-linux-amd64.tar.xz"
		wget --no-check-certificate "${DOWNLOADURL}"
		tar xf "trojan-$VERSION-linux-amd64.tar.xz"
		rm -f "trojan-$VERSION-linux-amd64.tar.xz"
		mkdir -p ${install_dir}/certificate
		echo $port > ${install_dir}/portinfo
		chmod -R 755 ${install_dir}
		cd trojan
                # 修改成GCP可用 ↓
		sed -i 's#local_port": 22#local_port": '${port}'#g' config.json
		password=$(cat /proc/sys/kernel/random/uuid)
		sed -i "s#password1#${password}#g" config.json
		password=$(cat /proc/sys/kernel/random/uuid)
		sed -i "s#password2#${password}#g" config.json
		sed -i 's#open": false#open": true#g' config.json
		cp examples/client.json-example ${install_dir}/certificate/config.json
                # 修改成GCP可用 ↓
		sed -i 's#remote_port": 22#remote_port": '${port}'#g' ${install_dir}/certificate/config.json
		sed -i 's#open": false#open": true#g' ${install_dir}/certificate/config.json
		clear && cd ${install_dir}/certificate
		sed -i 's#verify": true#verify": false#g' ${install_dir}/certificate/config.json
		sed -i 's#hostname": true#hostname": false#g' ${install_dir}/certificate/config.json
		echo -e "${Info}即將生成證書,輸入假資訊即可,任意鍵繼續..."
		char=`get_char`
		openssl req -newkey rsa:2048 -nodes -keyout private.key -x509 -days 3650 -out fullchain.cer
		cd ${install_dir}
		sed -i "s#/path/to/certificate.crt#${install_dir}/certificate/fullchain.cer#g" config.json
		sed -i "s#/path/to/private.key#${install_dir}/certificate/private.key#g" config.json
		sed -i "s#example.com#$(get_ip)#g" ${install_dir}/certificate/config.json
		sed -i 's#cert": "#cert": "fullchain.cer#g' ${install_dir}/certificate/config.json
		sed -i "s#sni\": \"#sni\": \"$(get_ip)#g" ${install_dir}/certificate/config.json
	else
		cd $install_dir
	fi
	nohup ./trojan &
	view_password
	echo -e "${Tip}證書以及用戶配置檔所在檔夾：${install_dir}/certificate"
        # 取消下面6列 ↓
	#echo -e "${Tip}請用ZeroTier的公網IP替換用戶配置檔config.json裏的內網IP\n"
	#echo -e "${Info}內網IP：$(red_font $(get_ip))"
	#echo -e "${Info}ZeroTier Address：$(red_font $(zerotier-cli info|awk '{print $3}'))"
	#read -p "請輸入ZeroTier Network ID：" netid
	#zerotier-cli join $netid
	echo -e "${Info}任意鍵回到主頁..."
	char=`get_char`
}
view_password(){
	clear
	ipinfo=$(get_ip)
	port=$(cat ${install_dir}/portinfo)
	pw_trojan=$(jq '.password' ${install_dir}/config.json)
	length=$(jq '.password | length' ${install_dir}/config.json)
	cat ${install_dir}/certificate/config.json | jq 'del(.password[])' > /root/temp.json
	cp /root/temp.json ${install_dir}/certificate/config.json
	for i in `seq 0 $[length-1]`
	do
		password=$(echo $pw_trojan | jq ".[$i]" | sed 's/"//g')
		Trojanurl="trojan://${password}@${ipinfo}:${port}?allowInsecure=1&tfo=1"
		echo -e "密碼：$(red_font $password)"
		echo -e "Trojan鏈結：$(green_font $Trojanurl)\n"
	done
	cat ${install_dir}/certificate/config.json | jq '.password[0]="'${password}'"' > /root/temp.json
	cp /root/temp.json ${install_dir}/certificate/config.json
	echo -e "${Info}IP：$(red_font ${ipinfo})"
	echo -e "${Info}埠：$(red_font ${port})"
	echo -e "${Info}當前用戶總數：$(red_font ${length})\n"
}
start_menu_trojan(){
	clear
	white_font "\n Trojan一鍵安裝腳本 \c" && red_font "[v${sh_ver}]"
	white_font "        -- 胖波比 --\n"
	yello_font '————————————————————————————'
	green_font ' 1.' '  查看Trojan鏈結'
	yello_font '————————————————————————————'
	green_font ' 2.' '  安裝Trojan'
	green_font ' 3.' '  卸載Trojan'
	yello_font '————————————————————————————'
	green_font ' 4.' '  退出腳本'
	yello_font "————————————————————————————\n"
	read -p "請輸入數位[1-4](默認:2)：" num
	[ -z $num ] && num=2
	case $num in
		1)
		view_password
		echo -e "${Info}任意鍵回到主頁..."
		char=`get_char`
		;;
		2)
		install_trojan
		;;
		3)
		kill -9 $(ps|grep trojan|awk '{print $1}')
		rm -rf $install_dir
		;;
		4)
		exit 1
		;;
		*)
		clear
		echo -e "${Error}請輸入正確數字 [1-4]"
		sleep 2s
		start_menu_trojan
		;;
	esac
	start_menu_trojan
}
start_menu_trojan
