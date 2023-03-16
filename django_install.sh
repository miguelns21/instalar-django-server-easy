#!/bin/bash
echo "==1== INICIANDO === "
sudo ln -svf /usr/bin/python3 /usr/bin/python
usuario=miguel

echo "==2== Actualizando el Sistema === "
sudo apt-get -qq update
sudo apt-get -qq upgrade

echo "==3== Instalamos las dependencia para usar PostgreSQL con Python/Django: === "
sudo apt-get -qq install build-essential libpq-dev python3-pip

echo "==4== Instalamos PostgreSQL Server: === "
sudo apt-get -qq install postgresql postgresql-contrib

echo "==5== Instalamos Nginx: === "
sudo apt-get -qq install nginx

echo "==6== Instalamos Supervisor: === "
sudo apt-get -qq install supervisor

echo "==7== Iniciamos Supervisor: === "
sudo systemctl enable supervisor
sudo systemctl start supervisor

echo "==8== Instalamos python3-venv y pip: === "
sudo apt-get -qq install python3-venv python3-pip

echo "==9== Configuramos PostgreSQL: === "
sudo su - postgres -c "createuser -s "$usuario
sudo su - postgres -c "createdb django_prod --owner "$usuario
sudo -u postgres psql -c "ALTER USER $usuario WITH PASSWORD '$usuario'"

# Creamos el usuario del sistema
# sudo adduser --system --quiet --shell=/bin/bash --home=/home/django --gecos 'django' --group django
# sudo gpasswd -a django sudo

echo "==10== Creamos el entorno virtual === "
python -m venv /home/$usuario/.venv
source /home/$usuario/.venv/bin/activate

echo "==11== Instalamos django === "
pip install -q Django

echo "==12== Clonamos el proyecto === "
read -p 'Indique la dirección del repo a clonar (https://github.com/falconsoft3d/django-father): ' gitrepo
git -C /home/$usuario clone $gitrepo
read -p 'Indique la el nombre de la carpeta del proyecto (django-father): ' project
read -p 'Indique el nombre de la app principal de Django (father): ' djapp

echo "==13== Instalamos las dependencias === "
pip install -q -r /home/$usuario/$project/requirements.txt

echo "==14== Instalamos Gunicorn === "
pip install -q gunicorn

guni=/home/$usuario/.venv/bin/gunicorn_start

touch $guni
chmod u+x $guni
echo '#!/bin/bash' > $guni
echo '' >> $guni
echo 'NAME="django_app"' >> $guni
echo 'DIR=/home/'$usuario'/'$project >> $guni
echo 'USER='$usuario >> $guni
echo 'GROUP='$usuario >> $guni
echo 'WORKERS=3' >> $guni
echo 'BIND=unix:/home/'$usuario'/gunicorn.sock' >> $guni
echo 'DJANGO_SETTINGS_MODULE='$djapp'.settings' >> $guni
echo 'DJANGO_WSGI_MODULE='$djapp'.wsgi' >> $guni
echo 'LOG_LEVEL=error' >> $guni
echo '' >> $guni
echo 'source /home/'$usuario'/.venv/bin/activate' >> $guni
echo '' >> $guni
echo 'export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE' >> $guni
echo 'export PYTHONPATH=$DIR:$PYTHONPATH' >> $guni
echo '' >> $guni
echo 'exec /home/'$usuario'/.venv/bin/gunicorn ${DJANGO_WSGI_MODULE}:application \' >> $guni
echo '  --name $NAME \' >> $guni
echo '  --workers $WORKERS \' >> $guni
echo '  --user=$USER \' >> $guni
echo '  --group=$GROUP \' >> $guni
echo '  --bind=$BIND \' >> $guni
echo '  --log-level=$LOG_LEVEL \' >> $guni
echo '  --log-file=-' >> $guni

echo "==15== Convertimos a Ejecutable el Fichero: gunicorn_start === "
chmod u+x /home/$usuario/.venv/bin/gunicorn_start

echo "==16== Configurando Supervisor === "
mkdir /home/$usuario/$project/logs
touch /home/$usuario/$project/logs/gunicorn-error.log
superapp=/home/$usuario/django_app.conf
touch $superapp
echo '[program:django_app]' >> $superapp
echo 'command=/home/$usuario/.venv/bin/gunicorn_start' >> $superapp
echo 'user=$usuario' >> $superapp
echo 'autostart=true' >> $superapp
echo 'autorestart=true' >> $superapp
echo 'redirect_stderr=true' >> $superapp
echo 'stdout_logfile=/home/'$usuario/$project'/logs/gunicorn-error.log' >> $superapp
sudo cp $superapp /etc/supervisor/conf.d/django_app.conf

echo "==17== Configurando Nginx ==="
ngxapp=/home/$usuario/django_app
touch $guni
echo 'upstream django_app {' > $ngxapp
echo '    server unix:/home/django/gunicorn.sock fail_timeout=0;' >> $ngxapp
echo '}' >> $ngxapp
echo ''  >> $ngxapp
echo 'server {'  >> $ngxapp
echo '    listen 80;'  >> $ngxapp
echo '' >> $ngxapp
echo '    # add here the ip address of your server'  >> $ngxapp
echo '    # or a domain pointing to that ip (like example.com or www.example.com)'  >> $ngxapp
read -p 'Indique la IP del servidor: ' serverip
echo '    server_name '$serverip';' >> $ngxapp
echo '' >> >> $ngxapp
echo '    keepalive_timeout 5;' >> $ngxapp
echo '    client_max_body_size 4G;' >> $ngxapp
echo '' >> $ngxapp
echo '    access_log /home/'$usuario'/logs/nginx-access.log;' >> $ngxapp
echo '    error_log /home/'$usuario'/logs/nginx-error.log;' >> $ngxapp
echo '' >> $ngxapp
echo '    location /static/ {' >> $ngxapp
echo '        alias /home/django/static/;' >> $ngxapp
echo '    }' >> $ngxapp
echo '' >> $ngxapp
echo '    # checks for static file, if not found proxy to app' >> $ngxapp
echo '    location / {' >> $ngxapp
echo '        try_files $uri @proxy_to_app;' >> $ngxapp
echo '    }' >> $ngxapp
echo '' >> $ngxapp
echo '    location @proxy_to_app {' >> $ngxapp
echo '      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> $ngxapp
echo '      proxy_set_header Host $http_host;' >> $ngxapp
echo '      proxy_redirect off;' >> $ngxapp
echo '      proxy_pass http://django_app;' >> $ngxapp
echo '    }' >> $ngxapp
echo '}' >> $ngxapp
# Le metemos la IP al settings al final
sudo echo 'from .settings import ALLOWED_HOSTS' >> /home/$usuario/$project/$djapp/localsettings.py
sudo echo 'ALLOWED_HOSTS += ["'$serverip'"]' >> /home/$usuario/$project/$djapp/localsettings.py
sudo echo 'STATIC_ROOT = "/home/"$usuario"/static/"' >> /home/$usuario/$project/$djapp/localsettings.py

sudo ln -s /etc/nginx/sites-available/django_app /etc/nginx/sites-enabled/django_app
sudo rm /etc/nginx/sites-enabled/default
sudo service nginx restart

echo "=== Finalizando ==="
python /home/$usuario/$project/manage.py makemigrations
python /home/$usuario/$project/manage.py migrate
python /home/$usuario/$project/manage.py collectstatic
sudo chown $usuario:$usuario /home/$usuario/* -R
sudo chown $usuario:$usuario /home/$usuario/.venv/* -R
sudo chown $usuario:$usuario /home/$usuario/.venv -R
sudo supervisorctl restart django_app
