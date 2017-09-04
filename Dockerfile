FROM  alpine:3.6

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND noninteractive \
	GRAFANA_VERSION=4.4.3 \
	CARBON_VERSION=1.0.2 \
	WHISPER_VERSION=1.0.2

RUN addgroup -S www &&\
		adduser -S -g 'www' www
		#addgroup -S grafana \

# Install all prerequisites
RUN apk add --update-cache --no-cache  \
	ca-certificates        \
	git \
	gcc \
	g++ \
	make \
	fontconfig \
	libffi-dev             \
	nginx \
	nodejs \
	nodejs-npm \
	openssl \
	python2-dev \
	supervisor \
	py2-cairo               \
	py2-pip                 \
	py-twisted             \
	&& rm -rf /var/cache/apk/*

RUN pip install pip==9.0.1   \
	&&  pip install              \
	Twisted==17.5.0              \
	django==1.11                 \
	django-tagging==0.4.5        \
	gunicorn==19.7.1             \
	pyparsing==2.2.0             \
	pytz==2017.2


RUN     npm install ini chokidar

# Checkout the stable branches of Graphite, Carbon and Whisper and install from there
RUN     mkdir /src
RUN     git clone https://github.com/graphite-project/whisper.git /src/whisper            &&\
	cd /src/whisper                                                                   &&\
	git checkout "${WHISPER_VERSION}"                                                   &&\
	python2 setup.py install

RUN     git clone https://github.com/graphite-project/carbon.git /src/carbon              &&\
	cd /src/carbon                                                                    &&\
	git checkout "${CARBON_VERSION}"                                                    &&\
	python2 setup.py install

RUN     git clone https://github.com/graphite-project/graphite-web.git /src/graphite-web  &&\
	cd /src/graphite-web                                                              &&\
	python2 setup.py install                                                           &&\
	pip install -r requirements.txt                                                   &&\
	python2 check-dependencies.py

# Install Grafana
RUN mkdir -p /src/grafana                                                                                    &&\
	  mkdir -p /opt/grafana                                                                                    &&\
	#wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-"${GRAFANA_VERSION}".linux-x64.tar.gz -O /src/grafana.tar.gz &&\
	wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.4.3.linux-x64.tar.gz -O /src/grafana.tar.gz &&\
	tar -xzf /src/grafana.tar.gz -C /opt/grafana --strip-components=1                                     &&\
	rm /src/grafana.tar.gz

# ----------------- #
#   Configuration   #
# ----------------- #

# Configure Whisper, Carbon and Graphite-Web
COPY     ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
COPY     ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
COPY     ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
COPY     ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
COPY     ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN     mkdir -p /opt/graphite/storage/whisper
RUN     touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index
RUN     chown -R www /opt/graphite/storage
RUN     chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper
RUN     chmod 0664 /opt/graphite/storage/graphite.db
RUN     cp /src/graphite-web/webapp/manage.py /opt/graphite/webapp
RUN     cd /opt/graphite/webapp/ && python manage.py migrate --run-syncdb --noinput

# Configure Grafana
COPY     ./grafana/custom.ini /opt/grafana/conf/custom.ini

# COPY the default dashboards
RUN     mkdir /src/dashboards
COPY     ./grafana/dashboards/* /src/dashboards/
COPY     ./grafana/set-local-graphite-source.sh /src/
RUN     mkdir /src/dashboard-loader
COPY     ./grafana/dashboard-loader/dashboard-loader.js /src/dashboard-loader/

# Configure nginx and supervisord
COPY     ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY     ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# ---------------- #
#   Expose Ports   #
# ---------------- #

# Grafana
EXPOSE  80

# Graphite web port
EXPOSE 81



# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord"]
