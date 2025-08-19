# 多阶段构建优化版 Dockerfile
# 第一阶段：构建环境
FROM debian:bullseye as builder

# 安装构建依赖
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    git build-essential cmake automake autoconf libtool pkg-config \
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev \
    libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev \
    uuid-dev libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev \
    nasm libogg-dev libspeex-dev libspeexdsp-dev libldns-dev python3-dev \
    libavformat-dev libswscale-dev libavresample-dev liblua5.2-dev \
    libopus-dev libpq-dev libsndfile1-dev libflac-dev libvorbis-dev \
    libshout3-dev libmpg123-dev libmp3lame-dev

# 克隆源码
RUN git clone https://github.com/signalwire/freeswitch /usr/src/freeswitch
RUN git clone https://github.com/signalwire/libks /usr/src/libs/libks
RUN git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
RUN git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp
RUN git clone https://github.com/signalwire/signalwire-c /usr/src/libs/signalwire-c

# 构建依赖库
RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j$(nproc --all) && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j$(nproc --all) && make install
RUN cd /usr/src/libs/signalwire-c && PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# 构建 FreeSWITCH
RUN cd /usr/src/freeswitch && ./bootstrap.sh -j
RUN cd /usr/src/freeswitch && ./configure
RUN cd /usr/src/freeswitch && make -j$(nproc) && make install

# 清理构建环境
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/src/*

# 第二阶段：运行时环境
FROM debian:bullseye-slim

# 复制构建结果
COPY --from=builder /usr/local/ /usr/local/
COPY --from=builder /etc/freeswitch /etc/freeswitch

# 安装运行时依赖
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    libssl1.1 libpcre3 libedit2 libsqlite3-0 libcurl4 \
    libogg0 libspeex1 libspeexdsp1 libldns2 libavformat58 \
    libswscale5 libavresample4 liblua5.2-0 libopus0 \
    libpq5 libsndfile1 libflac8 libvorbis0a libshout3 \
    libmpg123-0 libmp3lame0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 设置工作目录
WORKDIR /usr/local/freeswitch

# 启动命令
CMD ["/usr/local/freeswitch/bin/freeswitch"]
