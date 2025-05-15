https://192.168.2.6:8006/#v1:0:=node%2Fpve1:4:::::::


# to install run:

```
export PVE_USER="prometheus@pve"
export PVE_PASSWORD="your_password"
export PVE_HOST="192.168.2.6:8006"
sudo -E ./install.sh
```


# example node exporter systemd service file

```
[Unit]
Description=Node exporter
Documentation=https://github.com/prometheus/node_exporter
After=local-fs.target network-online.target network.target
Wants=local-fs.target network-online.target network.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
KillMode=process
Delegate=yes
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter  \
	'--path.procfs=/proc' \
	'--path.rootfs=/' \
	'--path.sysfs=/sys' \
	'--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

ExecStartPre=-/usr/sbin/iptables -A INPUT -p tcp --dport 9100 -m state --state NEW -j ACCEPT
```
