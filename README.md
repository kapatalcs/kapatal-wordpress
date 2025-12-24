# Kapatal Server Provisioning with SaltStack

This project automatically installs and configures WordPress, Docker, HAProxy, and MySQL on Ubuntu and Debian systems using SaltStack. This system also manages system users, hostname, time zone, and basic services.

## Features

- Create a private user and group named `kapatal`
- Setting `Europe/Istanbul` time zone and `kapatal.local` hostname
- Installation of necessary system tools (htop, dnsutils, etc.)
- Enabling IP forwarding
- For Ubuntu:**
  - Docker and Docker Compose setup
  - Configuring and launching Docker Compose for WordPress
  - Installing and configuring HAProxy
  - MySQL installation, user and database creation
- For Debian:**
  - Apache deactivation
  - Nginx + PHP installation
  - Manual installation and configuration of WordPress
  - Creation of a self-signed SSL certificate
---

## How to use

1. Clone the repo:
```bash
git clone https://github.com/kapatalcs/kapatal-wordpress.git
cd kapatal-wordpress
```

2. Provide the appropriate `pillar` data to the Minion.

3. Make sure that the `files/` folder is accessible to SaltStack:

- If you are going to work **locally** (`salt-call --local`), the directory structure should be:
     ```
     /srv/salt/
     ├── kapatal-wordpress.sls
     ├── top.sls
     ├── kapatal-pillar.sls
     └── files/
         ├── kapatal-sudo
         ├── docker-compose.yml
         ├── haproxy.cfg
         ├── nginx.conf
         ├── nginx-logrotate
         ├── wp_secrets.txt
         └── wp-config.php
     ```

   - If you are working with the **Salt master/minion** structure, place `kapatal-wordpress.sls` and the `files/` directory in the path defined in the `file_roots` of the master server (for example `/srv/salt/`).

4. Apply the salt state:

- **For local testing:**
```bash
sudo salt-call --local state.apply kapatal-wordpress
```

- **In Master/Minion environment:**
```bash
sudo salt "*" state.apply kapatal-wordpress
```

---

## Notes
- **Usage:**
- You can change the values in the state file such as username (kapatal), user home directory, etc. according to your environment and preferences.
- **Password Hashing:**
- You must put a real hash value in the `kapatal_password` variable.
- You can use the following command to generate the hash:
```bash
openssl passwd -6
```

- **Docker Usage (Ubuntu):**
- If you get `apt-key` warnings during the Docker installation, this state already adds the GPG key securely with `signed-by`.
- Make sure the Docker service is running:
```bash
systemctl status docker
```

- **HAProxy Configuration:**
- Make sure that the `/home/kptl/haproxy.cfg` file does not contain any configuration errors.
- You can use the following command for testing:
```bash
docker exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

- **MySQL Root Authority:**
- When `mysql_user.present` is used, `%` host is defined for the root account. This allows remote connections. For security reasons, it is recommended to restrict it to only the required IP.

- **Salt Modules:**
- In order to use `mysql` modules, dependencies such as `python3-mysqldb`, `python3-pymysql` must be installed on the minion (it is already loading in state).

- **Nginx and PHP on Debian Side:**
- `disable_apache` definition has been included to prevent the Apache service from starting automatically.
- Make sure that `/etc/nginx/nginx.conf` file is configured correctly for Nginx to work with `php-fpm`.

- **Backup Recommendation:**
- Backup configuration files such as `wp-config.php` and `haproxy.cfg` before editing them.
- If there is important data during database installation, backup before running.
  ---

## License

This project is licensed under the MIT license.
---

Feel free to send pull request for any suggestions or contributions!

© 2025 Kapatal
