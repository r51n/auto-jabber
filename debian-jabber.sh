#!/bin/sh

# DEBIAN-JABBER installation script version 0.1

##### GENERIC CONFIGURATION SECTION FOR DEBIAN 7/8 #####

# Detect Debian release name from /etc/os-release
# Sets variable RELEASENAME, which is used by other modules

OS="$(eval $(grep PRETTY_NAME /etc/os-release) ; echo ${PRETTY_NAME})"
echo "Running on $OS"

RELEASENAME="unsupported"

case $OS in
	"Debian GNU/Linux 7 (wheezy)") 
		RELEASENAME="wheezy"
		;;
	"Debian GNU/Linux 8 (jessie)") 
		RELEASENAME="jessie"
		;;
esac

echo "Release name: $RELEASENAME"

if [ x${RELEASENAME} = "xunsupported" ]; then
	echo "ERROR: Debian GNU/Linux 7 or 8 required, not found."
	exit
fi

### CHECK-INTERNET

# Check Internet connection

echo -n "Checking Internet connection: "
if wget -q -O - http://httpredir.debian.org/ >/dev/null ; then
	echo "Success"
else
	echo "FAILED."
	echo "ERROR: Internet connection required, not found."
# TODO: Save the script somewhere predictable
	echo "Check connection then re-run the script manually."
	exit
fi

# globally disable any installation dialogs
export DEBIAN_FRONTEND=noninteractive


# update APT source definitions to use mirror redirector
#
mv -f /etc/apt/sources.list /etc/apt/sources.list.orig
cat >/etc/apt/sources.list <<_EOF_
# Sane defaults
deb http://httpredir.debian.org/debian ${RELEASENAME} main
deb-src http://httpredir.debian.org/debian ${RELEASENAME} main
deb http://httpredir.debian.org/debian ${RELEASENAME}-updates main
deb-src http://httpredir.debian.org/debian ${RELEASENAME}-updates main
deb http://security.debian.org/ ${RELEASENAME}/updates main
deb-src http://security.debian.org/ ${RELEASENAME}/updates main
_EOF_

# Update base packages first
#
apt-get update -q
apt-get upgrade -y -q

# Install essential packages
#
apt-get install -y -q curl openssh-server tor privoxy iptables-persistent psmisc

# TORIFY privoxy config
#
echo "forward-socks5 / 127.0.0.1:9050 ." >>/etc/privoxy/config
echo "listen-address 127.0.0.1:8118" >>/etc/privoxy/config

# Start TOR and PRIVOXY services
#
service tor stop
service tor start
service privoxy stop
service privoxy start

## Wait for Tor to sync so we can torify

TOR_READY=0
TOR_TIMER=0
TOR_TIMEOUT=120

echo -n "Waiting for Tor.."

while [ x${TOR_READY} = "x0" ] && [ ${TOR_TIMER} -lt ${TOR_TIMEOUT} ]; do
	sleep 5
	echo -n "."
	if tail -10 /var/log/tor/log |grep Bootstrapped.100 >/dev/null ; then
		TOR_READY=1
	fi
	TOR_TIMER=$(($TOR_TIMER+5))
done

## Torify this session
if [ x${TOR_READY} = "x1" ]; then
	echo "Success."
	export http_proxy=http://127.0.0.1:8118 https_proxy=http://127.0.0.1:8118
else
	echo "Timeout."
	echo "Tor is DISABLED for this session."
fi

# Iptables persistent rules block non-Tor traffic
# DO NOT ENABLE unless you have SSH as a hidden service
#
cat >/etc/iptables/rules.v4.toronly <<_EOF_
*filter
:INPUT ACCEPT [46:3400]
:FORWARD ACCEPT [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -m owner --uid-owner debian-tor -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -d 192.168.0.0/16 -j ACCEPT
-A OUTPUT -d 172.16.0.0/12 -j ACCEPT
-A OUTPUT -d 10.0.0.0/8 -j ACCEPT
COMMIT
_EOF_

##### END OF GENERIC SECTION - SPECIFIC CONFIG BELOW THIS LINE #####

#
# Add official Prosody repository to APT sources
#    uses $RELEASENAME from generic config stub
#
cat >>/etc/apt/sources.list <<_EOF_
# Prosody official
deb http://packages.prosody.im/debian ${RELEASENAME} main
_EOF_

#
# Import official Prosody package signing key
# (from https://prosody.im/files/prosody-debian-packages.key)
#
apt-key add - <<_EOF_
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

mQGiBEoXOjERBAD2ygmSdiqsRmrTqUqcGoWmTU90DrikaYb3/rwwMhSloXT9qNuD
aOdJb/LNfwhiSbKF35JHgYV4+RIdwDLv4wNqmsQH1ZYOUi3j/1O5w2LV8lG816X2
NdGni+fGArtM68C9ZxdIDweo2V5G5StHINcKP/Cab08sUjyrrCpwO/Z5xwCg9H8L
PsFYns6RcnM7f6A6x5NHEVsEAL9RYChhkecv/+qnbDlKHOJT8TQT4S8p6RYtaZHE
XR73vvvj0P/6Lxw+tKZJqQmVpNaLXztLSNW3KfAR+Jz4SLBJoSP4uXJ5UVIUnqbp
HCUZ3BnDGeHuTplxtrYWmznE34KMks6riXoUApU/kmo8TFqh8aTEp1F/Zd9TdriQ
c0iCA/42SBlM3Ax0cbi2thHSEhUV6aCbs9R9H2Tmke0LswpUMTfxUT37b8t5ocbZ
iHoGdEVIC3ZK2Usu6IS5uhY4245iECafLUX4LF4uY17IHj713yOHZ8T9t2LAGFu9
oxM7EEoDyVK8Jg0fRn7srBC/p7MdBD1kwVaQOnIjqjiqf3e9sLQyUHJvc29keSBJ
TSBEZWJpYW4gUGFja2FnZXMgPGRldmVsb3BlcnNAcHJvc29keS5pbT6IYAQTEQIA
IAUCShc6MQIbAwYLCQgHAwIEFQIIAwQWAgMBAh4BAheAAAoJEHOT1+Z02du11MQA
nRsq54C4D1k/s0i0Tg41h1LDbAFtAKC2g53DYE3X8jPVJVBTFeHsnkztfLkEDQRK
FzsAEBAAwd9OI2tmqS0DR3Z8vxpio0eV/0+G4OObYEzjq4Keohw8u4qGVoDO4LPB
pyseNPv6J+eu+F2ONa04L1eODPAYprzjxU6gFgt+X2u7kjERybFDXBlVHUNDQIUM
hqpVHhslLGAk1tLJ0anIVwn7Lh4ft7IZq2/LrAb5SR1sSml4q6352jwqyxsNZv71
R+xHjVfj4SqE2FQ63YpQQQtKiPIc/u876m1bxC04KuR1buEjA0KlPHARjGW9dGf/
SzEy4FYcuLyNPUiRRH2AJ+b8wocefpXnbKKfHs+zL0j2KApAvSiiW0MN3qvXiXV5
aer7DVubXpzrS7VAeBJ6yzjqQTUWbYhmg2MKn6JixYI9y4w9ENGhkHcKp8RjOgdP
+hdzoyKQNSE51y1NzujQCefs85BaXKrImUvJJVziWEsTAiy0rT55+juDenjAmGlC
mCkNCTB0fbWI3HH3P6WdT3ft+jZkVuxHWTbyogGVYyVy3et29HnI+KJ4+94FbWvd
WdEOA2HD1EaPbkUtN1J39PoP0iDx0V1eKBrLGqMGXmDUAYjXBy9sEJz2CpLwzx3S
wizIgUv5hogLILassF05YB08DtLDk1EB7D+TSkBWG+G33r6DljTk5hrjWJCE1DK4
OfwGkwV9J75mDS36eTknEn4hxt2NSDOwXD/u0KeEKrrGGBZt918AAwUP/38LeUAs
c+7HeQmuWItZvTjAeQd71ECi0G/iIO+ccGYFvIKEMMUrJZQaGJpa3h8j1Eu8usEE
+3UULn6Wl5YpiCpIBpEystxnmqn2bxaKtDdFtD43hHV/eaCQuuLKN9qmx6VspdqH
SqN+1xbtkBqIBxONBLNusafByWUs15AUxFbLYqS5dPw3PNooHGLRvLtq3prO0F2j
BLKiujpNSWG/Q6u/AbxIn3qNiYOl201bKBQiYD/xCZEQZAfJSWC+EvU0fpDrTNy+
MArZniAGltAR4UyhJcqS3RAsB6b12ZpgreOpbTAJ3hET6bYmIwVPQfE/OfIRkZMm
jldn4zzRjMn9HiJjc/lvWJecmdzZ1NOKFCigz8luOHZeSXCS34THhi4fHZBzSKfD
FJXOmq79ouHTY0hyvVksk/tj3g7Oz3obFYDbb86XmAVlPvsmWTFO83DFS2ohA6ai
lvbRhTMOED4y5Ed5abFcfrziCTyPtZgm1OpeNibrOp85D2IzMHlqZTG/RWl5LtVU
wFSrv0OlEz2xD9RyrlIg9c4BUJNybErX1oZ08FVWQdmgff59XNNLv7bPPHYKCnaE
ou6SAY1PeEgmbONRJ6cR6dSVIMEAl8rFCIcL7jz/6S4CjMqST4D9MqDOeoDdl2Zm
ohKViNdLF+P2Oha6djBTxEjz1qhfcu7OVjGaiEkEGBECAAkFAkoXOwACGwwACgkQ
c5PX5nTZ27WmTQCg32XtVZ1E9KIPDpcpMrhV+4wpt50AnjSYtDgDGoWbRxhGDNK3
UqwePNWL
=/y9s
-----END PGP PUBLIC KEY BLOCK-----
_EOF_


#
# Install Prosody - official repository will take precedence version-wise
#
apt-get update
apt-get install -y -q prosody lua-bitop lua-sec

# Configure hidden service in TOR
cat >>/etc/tor/torrc <<_EOF_
### Prosody XMPP server c2s=5222 s2s=5269 ###
HiddenServiceDir /var/lib/tor/prosody/
HiddenServicePort 5222 127.0.0.1:5222
HiddenServicePort 5269 127.0.0.1:5269
#HiddenServicePort 22 127.0.0.1:22
#HiddenServicePort 5280 127.0.0.1:5280
#HiddenServicePort 5281 127.0.0.1:5281
_EOF_

# Restart Tor to generate service keys
service tor restart
sleep 1

# Install onions module (not included in repo package)
wget https://hg.prosody.im/prosody-modules/raw-file/tip/mod_onions/mod_onions.lua \
	-O /usr/lib/prosody/modules/mod_onions.lua
# TODO - verify file integrity

# Prosody package doesn't include conf.d by default
mkdir -p /etc/prosody/conf.d
if ! grep conf.d/ /etc/prosody/prosody.cfg.lua >/dev/null; then
	echo 'Include "conf.d/*.cfg.lua"' >>/etc/prosody/prosody.cfg.lua
fi

PROSODYHOST=`cat /var/lib/tor/prosody/hostname`

#
# Generate virtual host file - our XMPP service definition
#
VHOSTCONFIG=/etc/prosody/conf.d/$PROSODYHOST.cfg.lua
cat > $VHOSTCONFIG <<_EOF_
VirtualHost "${PROSODYHOST}"
  admins = { "admin@${PROSODYHOST}" }
  modules_enabled = { "onions" }
-- onions_socks5_host = "127.0.0.1"
-- onions_socks5_port = 9050
  onions_tor_all = true
  c2s_require_encryption = true
Component "conf.${PROSODYHOST}" "muc"
  modules_enabled = { "onions" }
  onions_tor_all = true
  c2s_require_encryption = true
_EOF_


#
# Restart Prosody with updated config
#
service prosody restart

#
# Create admin user and password
#
ADMINPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1`

(echo $ADMINPASS; echo $ADMINPASS) |prosodyctl adduser admin@${PROSODYHOST}

#
# Save settings to a file in root's home
#
echo "Hostname: " ${PROSODYHOST} >>/root/jabberconfig.txt
echo "Password: " ${ADMINPASS} >>/root/jabberconfig.txt

echo "COMPLETE"
cat /root/jabberconfig.txt
