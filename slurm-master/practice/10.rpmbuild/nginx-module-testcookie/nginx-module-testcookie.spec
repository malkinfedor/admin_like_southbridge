#
%define nginx_user nginx
%define nginx_group nginx

%if 0%{?rhel} || 0%{?amzn}
%define _group System Environment/Daemons
BuildRequires: openssl-devel
%endif

%if 0%{?suse_version} == 1315
%define _group Productivity/Networking/Web/Servers
BuildRequires: libopenssl-devel
%endif

%if 0%{?rhel} == 7
%define epoch 1
Epoch: %{epoch}
%define dist .el7
%endif

%define main_version 1.15.5
%define main_release 1%{?dist}.ngx
%define module_testcookie_version         1.24
%define module_testcookie_release         1%{?dist}.ngx

%define bdir %{_builddir}/%{name}-%{main_version}

Name: nginx-module-testcookie
Version: %{main_version}.%{module_testcookie_version}
Release: %{module_testcookie_release}
Group: %{_group}
Requires: nginx = %{?epoch:%{epoch}:}%{main_version}-%{main_release}
Summary: nginx testcookie module

Source0: http://nginx.org/download/nginx-%{main_version}.tar.gz
Source99: openssl-1.0.2p.tar.gz
Source100: testcookie-nginx-module-%{module_testcookie_version}.tar.gz

License: 2-clause BSD-like license

BuildRoot: %{_tmppath}/%{name}-%{main_version}-%{main_release}-root
BuildRequires: zlib-devel
BuildRequires: pcre-devel

%description 
Dynamic testcookie module for nginx.

%if 0%{?suse_version} || 0%{?amzn}
%debug_package
%endif

%define WITH_CC_OPT $(echo %{optflags} $(pcre-config --cflags))
%define WITH_LD_OPT -Wl,-z,relro -Wl,-z,now

%define BASE_CONFIGURE_ARGS $(echo "--prefix=%{_sysconfdir}/nginx --sbin-path=%{_sbindir}/nginx --modules-path=%{_libdir}/nginx/modules --conf-path=%{_sysconfdir}/nginx/nginx.conf --error-log-path=%{_localstatedir}/log/nginx/error.log --http-log-path=%{_localstatedir}/log/nginx/access.log --pid-path=%{_localstatedir}/run/nginx.pid --lock-path=%{_localstatedir}/run/nginx.lock --http-client-body-temp-path=%{_localstatedir}/cache/nginx/client_temp --http-proxy-temp-path=%{_localstatedir}/cache/nginx/proxy_temp --http-fastcgi-temp-path=%{_localstatedir}/cache/nginx/fastcgi_temp --http-uwsgi-temp-path=%{_localstatedir}/cache/nginx/uwsgi_temp --http-scgi-temp-path=%{_localstatedir}/cache/nginx/scgi_temp --user=%{nginx_user} --group=%{nginx_group} --with-openssl=./openssl-1.0.2p --with-openssl-opt=-fPIC --with-compat --with-file-aio --with-threads --with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module")
%define MODULE_CONFIGURE_ARGS $(echo "--add-dynamic-module=testcookie-nginx-module-%{module_testcookie_version}")

%prep
%setup -qcTn %{name}-%{main_version}
tar --strip-components=1 -zxf %{SOURCE0}
tar xvzf %SOURCE99
tar xvzf %SOURCE100



%build

cd %{bdir}
./configure %{BASE_CONFIGURE_ARGS} %{MODULE_CONFIGURE_ARGS} \
	--with-cc-opt="%{WITH_CC_OPT}" \
	--with-ld-opt="%{WITH_LD_OPT}" \
	--with-debug
make %{?_smp_mflags} modules
for so in `find %{bdir}/objs/ -type f -name "*.so"`; do
debugso=`echo $so | sed -e "s|.so|-debug.so|"`
mv $so $debugso
done
./configure %{BASE_CONFIGURE_ARGS} %{MODULE_CONFIGURE_ARGS} \
	--with-cc-opt="%{WITH_CC_OPT}" \
	--with-ld-opt="%{WITH_LD_OPT}"
make %{?_smp_mflags} modules

%install
cd %{bdir}
%{__rm} -rf $RPM_BUILD_ROOT


%{__mkdir} -p $RPM_BUILD_ROOT%{_libdir}/nginx/modules
for so in `find %{bdir}/objs/ -maxdepth 1 -type f -name "*.so"`; do
%{__install} -m755 $so \
   $RPM_BUILD_ROOT%{_libdir}/nginx/modules/
done

%{__mkdir} -p $RPM_BUILD_ROOT%{_datadir}/%{name}
%{__install} -m644 %{bdir}/testcookie-nginx-module-%{module_testcookie_version}/aes.min.js $RPM_BUILD_ROOT%{_datadir}/%{name}/

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{_libdir}/nginx/modules/*
%{_datadir}/%{name}/aes.min.js


%post
if [ $1 -eq 1 ]; then
cat <<BANNER
----------------------------------------------------------------------

The testcookie dynamic module for nginx has been installed.
To enable this module, add the following to /etc/nginx/nginx.conf
and reload nginx:

load_module modules/ngx_http_testcookie_access_module.so;

see doc at: https://github.com/kyprizel/testcookie-nginx-module
For using client-side cookie decryption use aes.min.js in /usr/share/nginx-module-testcookie

----------------------------------------------------------------------
BANNER
fi

%changelog
* Tue Dec 13 2016 Sergey Bondarev <s.bondarev@southbridge.ru>
- testcookie dynamic module
