# aws-elb

'aws-elb' provides LWRPs to manage ELBs, allowing creation and deletion and add and remove instances.

## LWRPs

All LWRPs accepts the following parameters:

* region: Amazon region to use
* access_key_id: the access key to use
* secret_access_key: the secret to use

### erp

This LWRP manages ELBs

#### Parameters

* listeners: it can be an string or integer representing the a port number, the symbols :http and :https to map
80->80 and 443->443, and :https_to_http to map 443->80. It may be an array of strings, numbers or symbols. Also,
it can be a map of elb_port->backend_port. Finally, it can be an instance of Chef::Resource::AwsElbElb::Listener
that has the ELB port and protocol and backend port and protocol and the associated certificate name.
* certificate: certificate name to attach to ELB SSL ports.
* vpc: the VPC name to create the ELB into
* subnets: subnet name or array of names to create the ELB into
* security_groups: the security group name or names to attach to ELB
* instances: instance name or names to add as backends. The name can be the id (id-xxxx), the name of a previously
create instance (aws_ec2_instance[XXXX]) or <name>@<subnet> to use the instance with the provided name residing
in the specified subnet.
* health: the health check. It can be a string 'PROTO:PORT' where PROTO can be TCP, SSL, HTTP or HTTPS. 'TCP:80' by default.
* health_interval: how many seconds between checks: 30 by default.
* health_timeout: how many seconds to mark the probe as failed. 5 by default.
* health_healthy: how many success probes to mark backend as ok. 10 by default.
* health_unhealthy: how many failed probes to mark instance as faulty. 2 by default.
