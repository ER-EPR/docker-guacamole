FROM library/tomcat:9.0.65-jre11-openjdk-bullseye

ENV ARCH=amd64 \
  GUAC_VER=1.5.2 \
  GUACAMOLE_HOME=/app/guacamole \
  PG_MAJOR=9.6 \
  PGDATA=/config/postgres \
  POSTGRES_USER=guacamole \
  POSTGRES_DB=guacamole_db \
  PSQLJDBC_VER=42.6.0 \
  LSB_RELEASE=bullseye

# Apply the s6-overlay

RUN curl -SLO "https://github.com/just-containers/s6-overlay/releases/download/v1.22.1.0/s6-overlay-${ARCH}.tar.gz" \
  && tar -xzf s6-overlay-${ARCH}.tar.gz -C / \
  && tar -xzf s6-overlay-${ARCH}.tar.gz -C /usr ./bin \
  && rm -rf s6-overlay-${ARCH}.tar.gz \
  && mkdir -p ${GUACAMOLE_HOME} \
    ${GUACAMOLE_HOME}/lib \
    ${GUACAMOLE_HOME}/extensions

WORKDIR ${GUACAMOLE_HOME}
# Change postgresql source
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt ${LSB_RELEASE}-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
  && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Install dependencies
RUN apt-get update && apt-get install -y rsyslog\
    libcairo2-dev libjpeg62-turbo-dev libpng-dev \
    libtool-bin uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev freerdp2-dev libpango1.0-dev \
    libssh2-1-dev libtelnet-dev libvncserver-dev libwebsockets-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev \
    ghostscript postgresql-${PG_MAJOR} \
  && rm -rf /var/lib/apt/lists/*

# Link FreeRDP to where guac expects it to be
RUN [ "$ARCH" = "armhf" ] && ln -s /usr/local/lib/freerdp /usr/lib/arm-linux-gnueabihf/freerdp || exit 0
RUN [ "$ARCH" = "amd64" ] && ln -s /usr/local/lib/freerdp /usr/lib/x86_64-linux-gnu/freerdp || exit 0

# Add make and gcc
RUN apt-get update && apt-get install -y build-essential

# Install guacamole-server  --with-init-dir=/etc/init.d

RUN curl -SLO "https://apache.org/dyn/closer.lua/guacamole/${GUAC_VER}/source/guacamole-server-${GUAC_VER}.tar.gz?action=download" \
  && tar -xzf guacamole-server-${GUAC_VER}.tar.gz \
  && cd guacamole-server-${GUAC_VER} \
  && ./configure --enable-allow-freerdp-snapshots \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && cd .. \
  && rm -rf guacamole-server-${GUAC_VER}.tar.gz guacamole-server-${GUAC_VER} \
  && ldconfig

# Install guacamole-client and postgres auth adapter
RUN set -x \
  && rm -rf ${CATALINA_HOME}/webapps/ROOT \
  && curl -SLo ${CATALINA_HOME}/webapps/ROOT.war "https://apache.org/dyn/closer.lua/guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war?action=download" \
  && curl -SLo ${GUACAMOLE_HOME}/lib/postgresql-${PSQLJDBC_VER}.jar "https://jdbc.postgresql.org/download/postgresql-${PSQLJDBC_VER}.jar" \
  && curl -SLO "https://apache.org/dyn/closer.lua/guacamole/${GUAC_VER}/binary/guacamole-auth-jdbc-${GUAC_VER}.tar.gz?action=download" \
  && tar -xzf guacamole-auth-jdbc-${GUAC_VER}.tar.gz \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/guacamole-auth-jdbc-postgresql-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions/ \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/schema ${GUACAMOLE_HOME}/ \
  && rm -rf guacamole-auth-jdbc-${GUAC_VER} guacamole-auth-jdbc-${GUAC_VER}.tar.gz

# Add optional extensions
RUN set -xe \
  && mkdir ${GUACAMOLE_HOME}/extensions-available \
  && for i in auth-ldap auth-duo auth-header auth-cas auth-openid auth-quickconnect auth-totp; do \
    echo "https://apache.org/dyn/closer.lua/guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz?action=download" \
    && curl -SLO "https://apache.org/dyn/closer.lua/guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz?action=download" \
    && tar -xzf guacamole-${i}-${GUAC_VER}.tar.gz \
    && cp guacamole-${i}-${GUAC_VER}/guacamole-${i}-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions-available/ \
    && rm -rf guacamole-${i}-${GUAC_VER} guacamole-${i}-${GUAC_VER}.tar.gz \
  ;done

ENV PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH
ENV GUACAMOLE_HOME=/config/guacamole

WORKDIR /config

COPY root /

EXPOSE 8080

ENTRYPOINT [ "/init" ]
