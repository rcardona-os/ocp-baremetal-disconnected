- creating quay-pod.service

```bash
echo -n '[Unit]
Description=Infra Container for Quay
Wants=network.target
After=network-online.target
Before=quay-postgres.service quay-redis.service

[Service]
Type=simple
RemainAfterExit=yes
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-pod-id
ExecStart=/usr/bin/podman pod create \
    --name quay-pod \
    --infra-image registry.access.redhat.com/ubi8/pause:8.7-6 \
    --publish 8443:8443 \
    --pod-id-file %t/%n-pod-id \
    --replace
ExecStop=-/usr/bin/podman pod stop --ignore --pod-id-file %t/%n-pod-id -t 10
ExecStopPost=-/usr/bin/podman pod rm --ignore -f --pod-id-file %t/%n-pod-id
PIDFile=%t/%n-pid
KillMode=none
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target' | tee quay-pod.service
```

__NOTE: this file should be place in the directory:  /etc/systemd/system/__

- creating quay-postgres.service

```bash
echo -n '[Unit]
Description=PostgreSQL Podman Container for Quay
Wants=network.target
After=network-online.target quay-pod.service
Requires=quay-pod.service

[Service]
Type=simple
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-cid
ExecStart=/usr/bin/podman run \
    --name quay-postgres \
    -v pg-storage:/var/lib/pgsql/data:Z \
    -e POSTGRESQL_USER=user \
    -e POSTGRESQL_PASSWORD=password \
    -e POSTGRESQL_DATABASE=quay \
    --pod=quay-pod \
    --conmon-pidfile %t/%n-pid \
    --cidfile %t/%n-cid \
    --cgroups=no-conmon \
    --replace \
    registry.redhat.io/rhel8/postgresql-10:1-203.1669834630

ExecStop=/usr/bin/podman stop --ignore --cidfile %t/%n-cid -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/%n-cid
PIDFile=%t/%n-pid
KillMode=none
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target' | tee quay-postgres.service
```

__NOTE: this file should be place in the directory:  /etc/systemd/system/__

- creating quay-redis.service

```bash
echo -n '[Unit]
Description=Redis Podman Container for Quay
Wants=network.target
After=network-online.target quay-pod.service
Requires=quay-pod.service

[Service]
Type=simple
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-cid
ExecStart=/usr/bin/podman run \
    --name quay-redis \
    -e REDIS_PASSWORD=password \
    --pod=quay-pod \
    --conmon-pidfile %t/%n-pid \
    --cidfile %t/%n-cid \
    --cgroups=no-conmon \
    --replace \
    registry.redhat.io/rhel8/redis-6:1-92.1669834635

ExecStop=-/usr/bin/podman stop --ignore --cidfile %t/%n-cid -t 10
ExecStopPost=-/usr/bin/podman rm --ignore -f --cidfile %t/%n-cid
PIDFile=%t/%n-pid
KillMode=none
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target' | tee quay-redis.service
```

__NOTE: this file should be place in the directory:  /etc/systemd/system/__




- creating quay-app.service

```bash
echo -n '[Unit]
Description=Quay Container
Wants=network.target
After=network-online.target quay-pod.service quay-postgres.service quay-redis.service
Requires=quay-pod.service quay-postgres.service quay-redis.service

[Service]
Type=simple
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-cid
ExecStart=/usr/bin/podman run \
    --name quay-app \
    -v /root/quay-install/quay-config:/quay-registry/conf/stack:Z \
    -v quay-storage:/datastorage:Z \
    --pod=quay-pod \
    --conmon-pidfile %t/%n-pid \
    --cidfile %t/%n-cid \
    --cgroups=no-conmon \
    --replace \
    registry.redhat.io/quay/quay-rhel8:v3.8.12

ExecStop=-/usr/bin/podman stop --ignore --cidfile %t/%n-cid -t 10
ExecStopPost=-/usr/bin/podman rm --ignore -f --cidfile %t/%n-cid
PIDFile=%t/%n-pid
KillMode=none
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target' | tee quay-app.service
```

__NOTE: this file should be place in the directory:  /etc/systemd/system/__

