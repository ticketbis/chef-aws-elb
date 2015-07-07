name 'aws-elb'
maintainer 'Alberto Tablado'
maintainer_email 'alberto.tablado@ticketbis.com'
source_url 'https://github.com/ticketbis/chef-aws-elb'
license 'Apache v2.0'
description 'Manage ELBs'
long_description IO.read(File.join(
  File.dirname(__FILE__), 'README.md'
  )
)
version '0.1.0'

depends 'aws-base'
