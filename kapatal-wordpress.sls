kapatal-group:
  group.present:
    - name: kapatal
    - gid: 2025

kapatal-user:
  user.present:
    - name: kapatal
    - uid: 2025
    - gid: 2025
    - home: /home/kptl
    - createhome: True
    - shell: /bin/bash
    - password: {{ pillar['kapatal_password'] }}
    - require:
      - group: kapatal-group

kapatal-sudo:
  file.managed:
    - name: /etc/sudoers.d/kapatal
    - source: salt://files/kapatal-sudo
    - mode: 0440

set_timezone:
  timezone.system:
    - name: Europe/Istanbul

set_hostname:
  file.managed:
    - name: /etc/hostname
    - contents: kapatal.local
    - mode: 0644

set_hostname_cmd:
  cmd.run:
    - name: hostnamectl set-hostname kapatal.local
    - unless: "test $(hostname) = 'kapatal.local'"

restart_hostnamed:
  cmd.run:
    - name: systemctl restart systemd-hostnamed
    - onchanges:
        - file: /etc/hostname

add_hosts_entry:
  file.blockreplace:
    - name: /etc/hosts
    - marker_start: "# START SALT MANAGED HOSTNAME"
    - marker_end: "# END SALT MANAGED HOSTNAME"
    - content: |
        {{ grains['fqdn_ip4'][0] }} kapatal.local
    - append_if_not_found: True
    - show_changes: True

install_packages:
  pkg.installed:
    - pkgs:
      - htop
      - tcptraceroute
      - iputils-ping
      - dnsutils
      - sysstat
      - mtr

enable_ip_forwarding:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

{%if grains['os'] == 'Ubuntu' %}

install_docker_gpg:
  cmd.run:
    - name: curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    - unless: test -f /usr/share/keyrings/docker-archive-keyring.gpg

install_docker_repo:
  pkgrepo.managed:
    - name: deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker.list
    - key_file: /usr/share/keyrings/docker-archive-keyring.gpg
    - require:
      - cmd: install_docker_gpg

install_docker:
  pkg.installed:
    - name: docker-ce
    - require:
      - pkgrepo: install_docker_repo

install_docker_compose:
  pkg.installed:
    - name: docker-compose
    - require:
      - pkg: install_docker

enable_docker_service:
  service.running:
    - name: docker
    - enable: True

add_kapatal_to_docker:
  user.present:
    - name: kapatal
    - groups:
      - docker
    - require:
      - pkg: install_docker

wordpress_compose_file:
  file.managed:
    - name: /home/kptl/docker-compose.yml
    - source: salt://files/docker-compose.yml
    - user: kapatal
    - group: kapatal
    - mode: 0644

start_wordpress:
  cmd.run:
    - name: docker-compose up -d
    - cwd: /home/kptl
    - user: kapatal
    - require:
      - file: wordpress_compose_file

install_haproxy_image:
  cmd.run:
    - name: docker pull haproxy:latest
    - unless: docker image ls haproxy:latest

run_haproxy:
  cmd.run:
    - name: >
        docker run -d --name haproxy 
        -p 443:443 
        -p 80:80 
        -v /home/kptl/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro 
        haproxy:latest
    - unless: docker ps -a --format "{% raw %}{{.Names}}{% endraw %}" | grep -w haproxy
    - require:
      - cmd: install_haproxy_image

haproxy_config:
  file.managed:
    - name: /home/kptl/haproxy.cfg
    - source: salt://files/haproxy.cfg
    - user: kapatal
    - group: kapatal
    - mode: 0644

restart_haproxy:
  cmd.run:
    - name: docker restart haproxy
    - watch:
        - file: haproxy_config

add_mysql_gpg_key:
  cmd.run:
    - name: |
        gpg --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C
        gpg --export B7B3B788A8D3785C | tee /etc/apt/trusted.gpg.d/mysql.gpg > /dev/null

refresh_apt_cache:
  cmd.run:
    - name: apt-get update
    - require:
      - cmd: add_mysql_gpg_key

install_mysql_server:
  pkg.installed:
    - name: mysql-server
    - refresh: True

install_mysql_python:
  pkg.installed:
    - pkgs:
      - python3-mysql.connector
      - python3-mysqldb
      - python3-pymysql

set_mysqlclient_env_vars:
  pip.installed:
    - name: mysqlclient
    - env_vars:
        CFLAGS: "-I/usr/include/mysql"
        LDFLAGS: "-L/usr/lib/mysql"

ensure_mysql_service_running:
  service.running:
    - name: mysql
    - enable: True
    - watch:
        - pkg: install_mysql_python

{% set db_name = pillar['wordpress_db_name'] %}
{% set db_user = pillar['wordpress_db_user'] %}
{% set db_password = pillar['wordpress_db_password'] %}
{% set mysql_root_password = pillar['mysql_root_password'] %}

mysql_bind_config:
  mysql_user.present:
    - name: root
    - password: {{ mysql_root_password }}
    - host: '%'

create_wordpress_database:
  mysql_database.present:
    - name: {{ db_name }}

create_wordpress_user:
  mysql_user.present:
    - name: {{ db_user }}
    - password: {{ db_password }}
    - host: '%'

grant_wordpress_user_permissions:
  mysql_grants.present:
    - grant: all privileges
    - database: "{{ db_name }}.*"
    - user: "{{ db_user }}"
    - host: '%'

{% endif %}

{% if grains['os'] == 'Debian' %}

disable_apache:
  service.dead:
    - name: apache2
    - enable: False
    - onlyif: test -x /usr/sbin/apache2

nginx:
  pkg.installed:
    - name: nginx

  service.running:
    - name: nginx
    - enable: True
    - watch:
      - file: /etc/nginx/nginx.conf
    -require:
      - service: disable_apache
      - pkg: nginx

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://files/nginx.conf
    - user: root
    - group: root
    - mode: 0644

/etc/logrotate.d/nginx:
  file.managed:
    - source: salt://files/nginx-logrotate
    - user: root
    - group: root
    - mode: 0644

nginx-restart-cron:
  cron.present:
    - name: "/bin/systemctl restart nginx"
    - user: root
    - minute: 0
    - hour: 0
    - daymonth: 1

create_ssl_certificate:
  cmd.run:
    - name: |
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/kartaca-selfsigned.key \
        -out /etc/ssl/certs/kartaca-selfsigned.crt \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Kartaca/OU=IT/CN=kartaca1.local"
    - creates: /etc/ssl/certs/kartaca-selfsigned.crt

restart_nginx:
  service.running:
    - name: nginx
    - enable: True
    - watch:
      - file: /etc/nginx/nginx.conf

install_php_packages:
  pkg.installed:
    - pkgs:
      - php
      - php-fpm
      - php-mysql
      - php-cli
      - php-curl
      - php-gd
      - php-xml
      - php-mbstring
      - php8.2-zip


ensure_php_fpm_running:
  service.running:
    - name: php8.2-fpm
    - enable: True
    - watch:
      - pkg: install_php_packages

download_wordpress:
  cmd.run:
    - name: wget https://wordpress.org/latest.tar.gz -P /tmp
    - unless: test -f /tmp/latest.tar.gz

extract_wordpress:
  cmd.run:
    - name: tar -xzf /tmp/latest.tar.gz -C /var/www/html
    - unless: test -d /var/www/html/wordpress

get_wp_secrets:
  cmd.run:
    - name: curl https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/wp_secrets.txt
    - unless: test -f /tmp/wp_secrets.txt

update_wp_config_with_keys:
  file.managed:
    - name: /var/www/html/wp-config.php
    - source: salt://files/wp_secrets.txt
    - mode: 0644
    - user: www-data
    - group: www-data
    - onlyif: test -f /tmp/wp_secrets.txt

{% set db_name = pillar.get('wordpress_db_name', '') %}
{% set db_user = pillar.get('wordpress_db_user', '') %}
{% set db_password = pillar.get('wordpress_db_password', '') %}
{% set db_host = pillar.get('wordpress_db_host', 'localhost') %}

create_wp_config:
  file.managed:
    - name: /var/www/html/wp-config.php
    - source: salt://files/wp-config.php
    - template: jinja
    - context:
        db_name: {{ db_name }}
        db_user: {{ db_user }}
        db_password: {{ db_password }}
        db_host: {{ db_host }}
    - mode: 0644
    - user: www-data
    - group: www-data



{% endif %}


