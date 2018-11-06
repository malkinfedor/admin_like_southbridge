Name:           arcconf
Version:        6.50
Release:        el7.southbridge
Summary:        Adaptec RAID config utility

Group:          System Environment/Base
License:        GPL
URL:            http://southbridge.ru/
Source0:        arcconf
BuildRoot:      %{_tmppath}/%{name}-%{version}
Requires:       compat-libstdc++-33

%description
This package contains Adaptec RAID config utility

%prep
echo empty prep

%build
echo empty build

%install
rm -rf $RPM_BUILD_ROOT
%{__install} -Dp -m0755 %{SOURCE0} %{buildroot}/usr/bin/arcconf

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
/usr/bin/arcconf

%changelog
* Thu Oct  4 2018 Sergey Bondarev <s.bondarev@southbridge.ru> - 6.50
- initial package
