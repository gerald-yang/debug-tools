grep 'amd64' list | grep 'dbgsym' | awk '{print $1}'> amd64

for i in `dpkg -l | grep '14.2.11-0ubuntu0.19.10.1~cloud2' | awk '{print $2}' | sed ':a;N;$!ba;s/\n/-dbgsym /g'`; do
	echo "search $i"
	PKG=$(grep "$i" amd64)
	if [ -z "$PKG" ]; then
		echo "$PKG not found"
	else
		echo "get $PKG"
		#wget https://launchpad.net/~ubuntu-cloud-archive/+archive/ubuntu/train-updates-ddeb/+files/$PKG
	fi
done
