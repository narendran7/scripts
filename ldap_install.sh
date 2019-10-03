#!/bin/bash
echo "LDAP Server configuration"
echo -e "Enter the name of the domain: "
read domain
echo -e "Enter the top level domain: "
read TLD
LDAP_DIR="/etc/openldap/slapd.d/cn=config"
Migration_DIR="/usr/share/migrationtools/"
echo "Installing Packages"
yum -y install openldap* migrationtools
echo -e "Generating Ldap Password"
slappasswd -s vagrant | tee /tmp/passwd.txt
cd $LDAP_DIR
sed -i "s/dc=my-domain,dc=com/dc=${domain},dc=${TLD}/g" olcDatabase={2}hdb.ldif
text=`cat /tmp/passwd.txt`
echo "olcRootPW:$text" >> olcDatabase={2}hdb.ldif
sed -i "s/dc=my-domain,dc=com/dc=${domain},dc=${TLD}/g" olcDatabase={1}monitor.ldif
systemctl start slapd &&  systemctl enable slapd
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap/
openssl req -new -x509 -nodes -out /etc/pki/tls/certs/"$domain"ldap.pem -keyout /etc/pki/tls/certs/"$domain"ldapkey.pem -days 365 -subj "/C=IN/ST=Chennai/L=Chennai/O=T2S/OU=IT/CN=$domain.$TLD"
echo -e "olcTLSCertificateFile: /etc/pki/tls/certs/"$domain"ldap.pem
olcTLSCertificateKeyFile: /etc/pki/tls/certs/"$domain"ldapkey.pem" >> /etc/openldap/slapd.d/cn=config/olcDatabase={2}hdb.ldif
cd $LDAP_DIR
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif -w vagrant
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif -w vagrant
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif -w vagrant
cd $Migration_DIR
sed -i "s/"padl.com"/"$domain.$TLD"/g" migrate_common.ph
sed -i "s/"dc=padl,dc=com"/"dc=$domain,dc=$TLD";/g" migrate_common.ph
sed -i "s/EXTENDED_SCHEMA = 0/EXTENDED_SCHEMA = 1/g" migrate_common.ph
touch /root/base.ldif
echo -e "dn: dc=$domain,dc=$TLD
objectClass: top
objectClass: dcObject
objectclass: organization
o: $domain $TLD
dc: $domain

dn: cn=Manager,dc=$domain,dc=$TLD
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,dc=$domain,dc=$TLD
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=$domain,dc=$TLD
objectClass: organizationalUnit
ou: Group" > /root/base.ldif

useradd ldapuser1 && echo "redhat" | passwd --stdin ldapuser1
useradd ldapuser2 && echo "redhat" | passwd --stdin ldapuser2

grep ":10[0-9][0-9]" /etc/passwd > /root/passwd
grep ":10[0-9][0-9]" /etc/group > /root/group
/usr/share/migrationtools/migrate_passwd.pl /root/passwd /root/users.ldif
/usr/share/migrationtools/migrate_group.pl root/group /root/groups.ldif
ldapadd -x -D "cn=Manager,dc=$domain,dc=$TLD" -f /root/base.ldif -w vagrant
ldapadd -x -D "cn=Manager,dc=$domain,dc=$TLD" -f /root/users.ldif -w vagrant 
ldapadd -x -D "cn=Manager,dc=$domain,dc=$TLD" -f /root/groups.ldif -w vagrant
systemctl stop firewalld
yum -y install rpcbind nfs-utils 
systemctl start rpcbind && systemctl enable rpcbind
systemctl start nfs && systemctl enable nfs
echo -e "/home *(rw,sync)" >> /etc/exports
systemctl restart nfs
