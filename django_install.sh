#!/bin/bash
echo "==1== INICIANDO === "
sudo ln -svf /usr/bin/python3 /usr/bin/python
usuario=miguel

echo "==2== Actualizando el Sistema === "
sudo apt-get -qq update
sudo apt-get -qq upgrade

echo "==3== Instalamos las dependencia para usar PostgreSQL con Python/Django: === "
sudo apt-get -qq install build-essential libpq-dev python3-pip curl

echo "==4== Instalamos PostgreSQL Server: === "
sudo apt-get -qq install postgresql postgresql-contrib

echo "==5== Instalamos Nginx: === "
sudo apt-get -qq install nginx

echo "==6== Instalamos python3-venv y pip: === "
sudo apt-get -qq install python3-venv python3-pip

echo "==7== Clonamos el proyecto === "
read -p 'Indique la dirección del repo a clonar (https://github.com/falconsoft3d/django-father): ' gitrepo
git -C /home/$usuario clone $gitrepo
read -p 'Indique la el nombre de la carpeta del proyecto (django-father): ' project
read -p 'Indique el nombre de la app principal de Django (father): ' djapp
read -p 'Indique la IP del servidor: ' serverip

echo "==8== Creamos el entorno virtual === "
python -m venv /home/$usuario/$project/.venv
source /home/$usuario/$project/.venv/bin/activate

echo "Temporal"
sudo apt install python3-pip libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0
cp /home/$usuario/$project/deploy/requirements.txt /home/$usuario/$project/requirements.txt

echo "==9== Instalamos django === "
pip install -q Django

echo "==10== Instalamos las dependencias === "
pip install -q -r /home/$usuario/$project/requirements.txt
pip install psycopg2-binary

echo "==11== Configuramos PostgreSQL: === "
sudo su - postgres -c "createuser -s "$usuario
sudo su - postgres -c "createdb '$project' --owner "$usuario
sudo -u postgres psql -c "ALTER USER $usuario WITH PASSWORD '$usuario'"

echo "==12== Instalamos Gunicorn === "
pip install -q gunicorn

echo "==13== Creamos el Socket en Systemd === "
gunisocket=/home/$usuario/$project/gunicorn.socket

echo '[Unit]' > $gunisocket
echo 'Description=gunicorn socket' >> $gunisocket
echo '' >> $gunisocket
echo '[Socket]' >> $gunisocket
echo 'ListenStream=/run/gunicorn.sock' >> $gunisocket
echo '' >> $gunisocket
echo '[Install]' >> $gunisocket
echo 'WantedBy=sockets.target' >> $gunisocket

sudo mv $gunisocket /etc/systemd/system/gunicorn.socket

echo "==14== Creamos el servicio Gunicorn en Systemd === "
guniservice=/home/$usuario/$project/gunicorn.service

echo '[Unit]' > $guniservice
echo 'Description=gunicorn daemon' >> $guniservice
echo 'Requires=gunicorn.socket' >> $guniservice
echo 'After=network.target' >> $guniservice
echo '' >> $guniservice
echo '[Service]' >> $guniservice
echo 'User='$usuario >> $guniservice
echo 'Group='$usuario >> $guniservice
echo 'WorkingDirectory=/home/'$usuario/$project >> $guniservice
echo 'ExecStart=/home/'$usuario/$project/'.venv/bin/gunicorn \' >> $guniservice
echo '          --access-logfile /home/'$usuario/$project'/logs/gunicorn-access.log \' >> $guniservice
echo '          --error-logfile /home/'$usuario/$project'/logs/gunicorn-err.log \' >> $guniservice
echo '          --workers 3 \' >> $guniservice
echo '          --bind unix:/run/gunicorn.sock \' >> $guniservice
echo '          '$djapp'.wsgi:application' >> $guniservice
echo '' >> $guniservice
echo '[Install]' >> $guniservice
echo 'WantedBy=multi-user.target' >> $guniservice

sudo mv $guniservice /etc/systemd/system/gunicorn.service

sudo systemctl start gunicorn.socket
sudo systemctl enable gunicorn.socket


echo "==15== Configurando Nginx ==="
ngxapp=/etc/nginx/sites-available/$project
sudo echo 'server {' > $ngxapp
sudo echo '    listen 80;'  >> $ngxapp
sudo echo '' >> $ngxapp
sudo echo '    server_name '$serverip';' >> $ngxapp
sudo echo '' >> $ngxapp
sudo echo '    keepalive_timeout 5;' >> $ngxapp
sudo echo '    client_max_body_size 4G;' >> $ngxapp
sudo echo '' >> $ngxapp
sudo echo '    access_log /home/'$usuario'/'$project'/logs/nginx-access.log;' >> $ngxapp
sudo echo '    error_log /home/'$usuario'/'$project'/logs/nginx-error.log;' >> $ngxapp
sudo echo '' >> $ngxapp
sudo echo '    location /static/ {' >> $ngxapp
sudo echo '        alias /home/'$usuario/$project'/staticfiles/;' >> $ngxapp
sudo echo '    }' >> $ngxapp
sudo echo '' >> $ngxapp
sudo echo '    location / {' >> $ngxapp
sudo echo '        include proxy_params;' >> $ngxapp
sudo echo '        proxy_pass http://unix:/run/gunicorn.sock;' >> $ngxapp
sudo echo '    }' >> $ngxapp
sudo echo '}' >> $ngxapp

# Le metemos la IP al settings al final
sudo echo 'from .settings import ALLOWED_HOSTS' > /home/$usuario/$project/$djapp/production.py
sudo echo 'ALLOWED_HOSTS += ["'$serverip'"]' >> /home/$usuario/$project/$djapp/production.py
sudo echo 'STATIC_ROOT = "/home/'$usuario'/static/"' >> /home/$usuario/$project/$djapp/production.py
sudo echo 'DEBUG = False' >> /home/$usuario/$project/$djapp/production.py

sudo ln -s /etc/nginx/sites-available/$project /etc/nginx/sites-enabled/$project
sudo rm /etc/nginx/sites-enabled/default
sudo service nginx restart

echo "=== Finalizando ==="
python /home/$usuario/$project/manage.py makemigrations
python /home/$usuario/$project/manage.py migrate
python /home/$usuario/$project/manage.py collectstatic --noinput


