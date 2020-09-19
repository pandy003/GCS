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
Info=`green_font [信息]` && Error=`red_font [错误]` && Tip=`yello_font [注意]`

[ $(id -u) != '0' ] && { echo -e "${Error}您必须以root用户运行此脚本"; exit 1; }

######系统检测组件######
check_sys(){
	#检查系统
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
	#检查系统安装命令
	if [[ ${release} == "centos" ]]; then
		PM='yum'
	else
		PM='apt'
	fi
}
#获取IP
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
#防火墙配置
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
	echo -e "${Info}防火墙设置完成！"
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
	curl -s https://install.zerotier.com | sudo bash
	if [ ! -d $install_dir ]; then
		port=443
		until [[ -z $(lsof -i:${port}) ]]
		do
			port=$[${port}+1]
		done
		add_firewall
		firewall_restart
		VERSION=1.15.1
		DOWNLOADURL="https://github.com/trojan-gfw/trojan/releases/download/v${VERSION}/trojan-${VERSION}-linux-amd64.tar.xz"
		wget --no-check-certificate "${DOWNLOADURL}"
		tar xf "trojan-$VERSION-linux-amd64.tar.xz"
		rm -f "trojan-$VERSION-linux-amd64.tar.xz"
		mkdir -p ${install_dir}/certificate
		echo $port > ${install_dir}/portinfo
		chmod -R 755 ${install_dir}
		cd trojan
		sed -i 's#local_port": 443#local_port": '${port}'#g' config.json
		password=$(cat /proc/sys/kernel/random/uuid)
		sed -i "s#password1#${password}#g" config.json
		password=$(cat /proc/sys/kernel/random/uuid)
		sed -i "s#password2#${password}#g" config.json
		sed -i 's#open": false#open": true#g' config.json
		cp examples/client.json-example ${install_dir}/certificate/config.json
		sed -i 's#remote_port": 443#remote_port": '${port}'#g' ${install_dir}/certificate/config.json
		sed -i 's#open": false#open": true#g' ${install_dir}/certificate/config.json
		clear && cd ${install_dir}/certificate
		sed -i 's#verify": true#verify": false#g' ${install_dir}/certificate/config.json
		sed -i 's#hostname": true#hostname": false#g' ${install_dir}/certificate/config.json
		echo -e "${Info}即将生成证书,输入假信息即可,任意键继续..."
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
	echo -e "${Tip}证书以及用户配置文件所在文件夹：${install_dir}/certificate"
	echo -e "${Tip}请用ZeroTier的公网IP替换用户配置文件config.json里的内网IP\n"
	echo -e "${Info}内网IP：$(red_font $(get_ip))"
	echo -e "${Info}ZeroTier Address：$(red_font $(zerotier-cli info|awk '{print $3}'))"
	read -p "请输入ZeroTier Network ID：" netid
	zerotier-cli join $netid
	echo -e "${Info}任意键回到主页..."
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
		echo -e "密码：$(red_font $password)"
		echo -e "Trojan链接：$(green_font $Trojanurl)\n"
	done
	cat ${install_dir}/certificate/config.json | jq '.password[0]="'${password}'"' > /root/temp.json
	cp /root/temp.json ${install_dir}/certificate/config.json
	echo -e "${Info}IP：$(red_font ${ipinfo})"
	echo -e "${Info}端口：$(red_font ${port})"
	echo -e "${Info}当前用户总数：$(red_font ${length})\n"
}
start_menu_trojan(){
	clear
	white_font "\n Trojan一键安装脚本 \c" && red_font "[v${sh_ver}]"
	white_font "        -- 胖波比 --\n"
	yello_font '————————————————————————————'
	green_font ' 1.' '  查看Trojan链接'
	yello_font '————————————————————————————'
	green_font ' 2.' '  安装Trojan'
	green_font ' 3.' '  卸载Trojan'
	yello_font '————————————————————————————'
	green_font ' 4.' '  退出脚本'
	yello_font "————————————————————————————\n"
	read -p "请输入数字[1-4](默认:2)：" num
	[ -z $num ] && num=2
	case $num in
		1)
		view_password
		echo -e "${Info}任意键回到主页..."
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
		echo -e "${Error}请输入正确数字 [1-4]"
		sleep 2s
		start_menu_trojan
		;;
	esac
	start_menu_trojan
}
start_menu_trojan