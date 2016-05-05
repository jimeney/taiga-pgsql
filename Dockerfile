FROM debian:jessie

MAINTAINER “James Coleman-Powell“
EXPOSE 80
EXPOSE 5432
ENV DEBIAN_FRONTEND noninteractive


VOLUME [ "$DATA/static", \
         "$DATA/media" ]
VOLUME /var/lib/postgresql/data

# Install PostgreSQL
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

ENV PG_MAJOR 9.5
ENV PG_VERSION 9.5.2-1.pgdg80+1

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update \
	&& apt-get install -y postgresql-common \
	&& apt-get install -y \
		postgresql-$PG_MAJOR=$PG_VERSION \
		postgresql-contrib-$PG_MAJOR=$PG_VERSION \
	&& rm -rf /var/lib/apt/lists/*


# OS & Python env deps for taiga-back
RUN apt-get update -qq \
    && apt-get install -y -- build-essential binutils-doc autoconf flex \
        bison libjpeg-dev libfreetype6-dev zlib1g-dev libzmq3-dev \
        libgdbm-dev libncurses5-dev automake libtool libffi-dev curl git \
        tmux gettext python3.4 python3.4-dev python3-pip libxml2-dev \
        libxslt-dev libpq-dev virtualenv \
        nginx \
    && rm -rf -- /var/lib/apt/lists/*

RUN pip3 install circus gunicorn

# Create taiga user
ENV USER taiga
ENV UID 1000
ENV GROUP www-data
ENV HOME /home/$USER
ENV DATA /opt/taiga
RUN useradd -u $UID -m -d $HOME -s /usr/sbin/nologin -g $GROUP $USER
RUN mkdir -p $DATA $DATA/media $DATA/static $DATA/logs /var/log/taiga \
    && chown -Rh $USER:$GROUP $DATA /var/log/taiga

# Install taiga-back
USER $USER
WORKDIR $DATA
RUN git clone -b stable https://github.com/taigaio/taiga-back.git $DATA/taiga-back \
    && virtualenv -p /usr/bin/python3.4 venvtaiga \
    && . venvtaiga/bin/activate \
    && cd $DATA/taiga-back \
    && pip3 install -r requirements.txt \
    && deactivate

# Install taiga-front (compiled)
RUN git clone -b stable https://github.com/taigaio/taiga-front-dist.git $DATA/taiga-front-dist

USER root

# Cleanups
RUN rm -f /etc/nginx/sites-enabled/default

# Copy template seeds
COPY seeds/*.tmpl /tmp/

COPY launch /

# Initialize postgres database
ADD resources/sql/postgresql-init.sql /tmp/
RUN /etc/init.d/postgresql start && sleep 2 && su postgres -c "cd /tmp ; psql -a -f postgresql-init.sql &&  exit"

# Hack posgresql configuration so it can be launched in foreground mode
RUN sed -i 's/^auto.*$/manual/g' /etc/postgresql/9.5/main/start.conf

# Add shell script to launch postgres in foreground mode
ADD resources/usr/local/bin/postgresql.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/postgresql.sh

# Install supervisord
# Usefull to start and monitor multiple processes (easier than systemd in a docker context)
RUN apt-get update
RUN apt-get install -y --no-install-recommends supervisor
ADD resources/etc/supervisor/ /etc/supervisor/

# Command to start on container default run
CMD ["/usr/bin/supervisord"]
