include Chef::AwsEc2::Credentials

def whyrun_supported?
  true
end

use_inline_resources

attr_accessor :vpc, :listeners, :subnets, :security_groups

def load_current_resource
  self.current_resource = Chef::Resource.resource_for_node(new_resource.declared_type, node).new @new_resource.name
  current_resource.client = Chef::AwsEc2.get_elb_client(aws_credentials, aws_region)
  begin current_resource.elb = @current_resource.client.describe_load_balancers(load_balancer_names: [current_resource.name], page_size: 1).load_balancer_descriptions.first
  rescue Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
  end
  current_resource.iam_client = Chef::AwsEc2.get_iam_client(aws_credentials, aws_region)
  current_resource.ec2_client = Chef::AwsEc2.get_client(aws_credentials, aws_region)
  unless current_resource.elb.nil?
    self.listeners = current_resource.elb.listener_descriptions.map do |d|
      d.listener
    end
    self.subnets = current_resource.elb.subnets.map do |s|
      Aws::EC2::Subnet.new id: s, client: current_resource.ec2_client
    end
    self.security_groups = current_resource.elb.security_groups.map do |s|
      Aws::EC2::SecurityGroup.new id: s, client: current_resource.ec2_client
    end
    current_resource.instances current_resource.elb.instances.map{|i| i.instance_id}
    h = current_resource.elb.health_check
    current_resource.health h.target
    current_resource.health_timeout h.timeout
    current_resource.health_interval h.interval
    current_resource.health_healthy h.healthy_threshold
    current_resource.health_unhealthy h.unhealthy_threshold
  end
end

action :create do
  vpc = Chef::AwsEc2.get_vpc(new_resource.vpc, current_resource.ec2_client)
  fail "Unknown VPC '#{vpc}'" if vpc.nil?
  l = canonicalize_listeners new_resource.listeners
  s = new_resource.subnets.map do |s|
    t = Chef::AwsEc2.get_subnet(vpc, s)
    fail "Unknown subnet '#{s}' in VPC '#{new_resource.vpc}'" if t.nil?
    t
  end
  sg = new_resource.security_groups.map do |s|
    t = Chef::AwsEc2.get_security_group(vpc, s)
    fail "Unknown security group '#{s}' in VPC '#{new_resource.vpc}'" if t.nil?
    t
  end
  its = new_resource.instances.map do |i|
    next i if /^i-/ =~ i
    unless /(.*)@(.*)/ =~ i
      begin r = new_resource.resources("aws_ec2_instance[#{i}]")
      rescue then next
      end
      i = r.name + '@' + r.subnet
    end
    if /(.*)@(.*)/ =~ i
      subnet = Chef::AwsEc2.get_subnet(vpc, $2)
      fail "Unknown subnet '#{$2}' in VPC '#{new_resource.vpc}'" if subnet.nil?
      t = Chef::AwsEc2.get_instance($1, subnet)
      fail "Unknow instance '#{i}' in subnet '#{$2}' in VPC '#{new_resource.vpc}'" if t.nil?
      t.id
    else
      nil
    end
  end.compact
  converge_by "Creating ELB #{@new_resource.name}" do
    current_resource.client.create_load_balancer(load_balancer_name: current_resource.name,
      listeners: l, subnets: s.map{|s| s.id}, security_groups: sg.map{|sg| sg.id}
    )
    load_current_resource
  end unless current_resource.exist?
  (self.listeners - l).each do |l|
    converge_by "Deleting listener on port #{l.load_balancer_port}" do
      current_resource.client.delete_load_balancer_listeners(load_balancer_name: current_resource.name, load_balancer_ports: [l.load_balancer_port] )
    end
  end
  (l - self.listeners).each do |l|
    converge_by "Creating listener #{l.protocol}(#{l.load_balancer_port}) -> #{l.instance_protocol}(#{l.instance_port})" do
      current_resource.client.create_load_balancer_listeners(load_balancer_name: current_resource.name, listeners: [l] )
    end
  end
  (s - subnets).each do |s|
    name = s.tags.find { |t| t.key == 'Name'}.value
    name ||= s.id
    converge_by "Attaching to subnet '#{name}'" do
      current_resource.client.attach_load_balancer_to_subnets(load_balancer_name: new_resource.name, subnets: [ s.id ])
    end
  end
  (subnets - s).each do |s|
    name = s.tags.find { |t| t.key == 'Name'}.value
    name ||= s.id
    converge_by "Detaching from subnet '#{name}'" do
      current_resource.client.detach_load_balancer_from_subnets(load_balancer_name: new_resource.name, subnets: [ s.id ])
    end
  end
  converge_by "Setting security groups #{sg.map{|s| s.group_name}}" do
    current_resource.client.apply_security_groups_to_load_balancer(load_balancer_name: new_resource.name, security_groups: sg.map{|s| s.id})
  end unless security_groups == sg
  (its - current_resource.instances).each do |i|
    converge_by "Attaching instance '#{i}'" do
      current_resource.client.register_instances_with_load_balancer(load_balancer_name: new_resource.name, instances: [{ instance_id: i }])
    end
  end
  (current_resource.instances - its).each do |i|
    converge_by "Detaching instance '#{i}'" do
      current_resource.client.deregister_instances_from_load_balancer(load_balancer_name: new_resource.name, instances: [{ instance_id: i }])
    end
  end
  unless current_resource.health == new_resource.health and
    current_resource.health_interval == new_resource.health_interval and
    current_resource.health_timeout == new_resource.health_timeout and
    current_resource.health_healthy == new_resource.health_healthy and
    current_resource.health_unhealthy == new_resource.health_unhealthy

    m = new_resource.health.match(%r'(TCP|SSL|HTTP|HTTPS):([0-9]+)(/.*)?')
    fail "Invalid target spec '#{new_resource.health}'. It must be proto:port[/path]" if m.nil?
    fail "HTTP and HTTPS need a path: (HTTP|HTTPS):port/path" if (m[1] == 'HTTP' or m[1] == 'HTTPS') and m[3].nil?
    h = {target: new_resource.health, interval: new_resource.health_interval, timeout: new_resource.health_timeout,
      healthy_threshold: new_resource.health_healthy, unhealthy_threshold: new_resource.health_unhealthy}
    converge_by "Changing health to check #{new_resource.health} every #{new_resource.health_interval} seconds waiting #{new_resource.health_timeout} seconds. Mark invalid after #{new_resource.health_unhealthy} attemps and valid again after #{new_resource.health_healthy} attempts." do
      current_resource.client.configure_health_check(load_balancer_name: new_resource.name, health_check: h)
    end
  end
end

action :delete do
  converge_by "Deleting ELB #{@new_resource.name}" do
    current_resource.client.delete_load_balancer(load_balancer_name: current_resource.name)
  end if current_resource.exist?
end

private

def canonicalize_listeners l
  return if l.nil?
  listener = Chef::Resource::AwsElbElb::Listener
  l = [ l ] unless l.instance_of? Array
  l = l.map do |k,v|
    listener.new :tcp, k.to_i, :tcp, v.to_i
  end if l.instance_of? Hash
  l = l.map do |e|
    e = listener.new :http, 80, :http, 80 if e == :http
    e = listener.new :https, 443, :https, 443 if e == :https
    e = listener.new :https, 443, :http, 80 if e == :https_to_http
    if e.instance_of? Hash
       e = listener.new().update!(e)
       e.proto = :tcp if e.proto.nil? and !e.port.nil?
       e.to_proto = e.proto if e.to_proto.nil?
       e.to_port = e.port if e.to_port.nil?
    end
    case e
    when String then Aws::ElasticLoadBalancing::Types::listener.new(
        protocol: 'TCP', load_balancer_port: e.to_i, instance_protocol: 'TCP', instance_port: e.to_i, ssl_certificate_id: nil
      )
    when Integer then Aws::ElasticLoadBalancing::Types::listener.new(
        protocol: 'TCP', load_balancer_port: e, instance_protocol: 'TCP', instance_port: e, ssl_certificate_id: nil
      )
    when listener then Aws::ElasticLoadBalancing::Types::Listener.new(
        protocol: e.proto.to_s.upcase, load_balancer_port: e.port, instance_protocol: e.to_proto.to_s.upcase, instance_port: e.to_port, ssl_certificate_id: e.certificate
      )
    else fail "Invalid format for listener: #{e.class}"
    end
  end
  l = l.map do |e|
    t = e.clone
    next t if t.protocol == 'HTTP' or t.protocol == 'TCP'
    t.ssl_certificate_id = new_resource.certificate if t.ssl_certificate_id.nil?
    fail "Listener #{t.inspect} must have a certificate" if t.ssl_certificate_id.nil?
    c = Chef::AwsEc2.get_certificate(t.ssl_certificate_id, current_resource.iam_client)
    fail "Unknown certificate '#{t.ssl_certificate_id}'" if c.nil?
    t.ssl_certificate_id = c.server_certificate_metadata.arn
    t
  end
  l
end
