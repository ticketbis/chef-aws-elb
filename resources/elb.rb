actions :create, :delete

default_action :create

attribute :name, kind_of: String, name_attribute: true
attribute :listeners, kind_of: [String, Integer, Symbol, Array], required: true
attribute :certificate, kind_of: String
attribute :vpc, kind_of: String, required: true
attribute :subnets, kind_of: [String, Array], required: true
attribute :security_groups, kind_of: [String, Array]
attribute :instances, kind_of: [String, Array]
attribute :health, kind_of: [String, Symbol], default: 'TCP:80'
attribute :health_interval, kind_of: Integer, default: 30
attribute :health_timeout, kind_of: Integer, default: 5
attribute :health_healthy, kind_of: Integer, default: 10
attribute :health_unhealthy, kind_of: Integer, default: 2
attribute :region, kind_of: String
attribute :access_key_id, kind_of: String
attribute :secret_access_key, kind_of: String

attr_accessor :client, :ec2_client, :iam_client, :elb

def exist?
  !elb.nil?
end

Listener = Struct.new :proto, :port, :to_proto, :to_port, :certificate
class Listener
  def update!(other)
    members.each do |k|
      self[k] = other[k] if other.respond_to? :has_key? and other.has_key? k and !other[k].nil?
    end
    self
  end
end

def after_created
  subnets([ subnets ]) unless @subnets.nil? or subnets.instance_of? Array
  security_groups([ security_groups ]) unless @security_groups.nil? or security_groups.instance_of? Array
  instances([]) if @instances.nil?
  instances([ instances ]) unless instances.instance_of? Array
end
