# PowerDNS Module for ComputeStacks


#### PowerDNS Configuration

Configure PowerDNS to allow external API access. Be sure to restrict access to a particular IP or range only.

```
api=yes
api-key=GENERATE_API_KEY
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=0.0.0.0/0,104.42.109.231/32
webserver-password=GENERATE_PASSWORD
```

#### Example:

Example connecting to Master-Slave PowerDNS Setup. Standalone PowerDNS server will use 'Native' zone type.

```
Pdns.config[:zone_type] = 'Master'
Pdns.config[:masters] = ['ns1.computestacks.net.']
Pdns.config[:nameservers] = ['ns1.computestacks.net.', 'ns2.computestacks.net.']

auth = Pdns::Auth.new(0, 'admin', 'CHANGEMENOW', 'CHANGEME')
client = Pdns::Client.new('http://ns1.computestacks.net:8081/api/v1/servers', auth)
zone = Pdns::Dns::Zone.new(client, nil)
zone.name = 'mydomain.net'
zone.save
```
