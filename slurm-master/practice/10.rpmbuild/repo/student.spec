Name:           student
Version:        1.0
Release:        el7.slurm
Summary:        YUM configuration for Student slurm repository

Group:          System Environment/Base
License:        GPL
URL:            http://slurm.io/
Source0:        RPM-GPG-KEY-student
Source1:	student.repo
BuildRoot:      %{_tmppath}/%{name}-%{version}
BuildArchitectures: noarch

Requires:       yum

%description
This package contains yum configuration for the student RPM Repository,
as well as the public GPG keys used to sign them.

%prep
echo empty prep

%build
echo empty build

%install
rm -rf $RPM_BUILD_ROOT
%{__install} -Dp -m0644 %{SOURCE0} %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-student
%{__install} -Dp -m0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/yum.repos.d/%{name}.repo

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%config %{_sysconfdir}/yum.repos.d/%{name}.repo
%config %{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-student

%changelog
* Thu Oct  4 2018 Sergey Bondarev <s.bondarev@southbridge.ru> - 6.50
- initial package
