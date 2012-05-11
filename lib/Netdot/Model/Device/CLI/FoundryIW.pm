package Netdot::Model::Device::CLI::FoundryIW;

use base 'Netdot::Model::Device::CLI';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Device::CLI::FoundryIW - Foundry IronWare Class

=head1 SYNOPSIS

 Overrides certain methods from the Device CLI class

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 get_arp - Fetch ARP tables

  Arguments:
    None
  Returns:
    Hashref
  Examples:
    my $cache = $self->get_arp(%args)
=cut
sub get_arp {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_arp');
    my $host = $self->fqdn;
    return $self->_get_arp_from_cli(host=>$host);
}

############################################################################
=head2 get_fwt - Fetch forwarding tables

  Arguments:
    None
  Returns:
    Hashref
  Examples:
    my $fwt = $self->get_fwt(%args)
=cut
sub get_fwt {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_fwt');
    my $host = $self->fqdn;
    return $self->_get_fwt_from_cli(host=>$host);
}


############################################################################
#_get_arp_from_cli - Fetch ARP tables via CLI
#
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_get_arp_from_cli();
#
#
sub _get_arp_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_arp_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show arp', personality=>'foundry');
    # If you have defined VRF, you can uncomment the following lines:
    # # Get additional ARP Tables for VRF 'vrf1' and 'vrf2':
    # @output = (@output, $self->_cli_cmd(%$args, host=>$host, cmd=>'show arp vrf vrf1', personality=>'foundry'));
    # @output = (@output, $self->_cli_cmd(%$args, host=>$host, cmd=>'show arp vrf vrf2', personality=>'foundry'));

    # MAP interface names to IDs
    # Get all interface IPs for subnet validation
    my %int_names;
    my %devsubnets;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
	foreach my $ip ( $int->ips ){
	    push @{$devsubnets{$int->id}}, $ip->parent->_netaddr 
		if $ip->parent;
	}
    }

    my %cache;
    # Lines look like this:
    # 0    130.223.10.1        8071.1f63.ec91      Dynamic     0        1/4
    my ($iname, $ip, $mac, $intid);
    foreach my $line ( @output ) {
	chomp($line);
	if ( $line =~ /\d+\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+(\w{4}\.\w{4}\.\w{4})\s+\S+\s+\d+\s+(\S+)/ ) {
	    $ip    = $1;
	    $mac   = $2;
	    $iname = $3;
	}else{
	    $logger->debug(sub{"Device::CLI::FoundryIW::_get_arp_from_cli: line did not match criteria: $line" });
	    next;
	}
	$iname = $self->_reduce_iname($iname);
	my $intid = $int_names{$iname};

	unless ( $intid ) {
	    $logger->warn("Device::CLI::FoundryIW::_get_arp_from_cli: $host: Could not match $iname to any interface name");
	    next;
	}
	
	my $validmac = PhysAddr->validate($mac); 
	if ( $validmac ){
	    $mac = $validmac;
	}else{
	    $logger->debug(sub{"Device::CLI::FoundryIW::_get_arp_from_cli: $host: Invalid MAC: $mac" });
	    next;
	}	

	if ( Netdot->config->get('IGNORE_IPS_FROM_ARP_NOT_WITHIN_SUBNET') ){
	    # Don't accept entry if ip is not within this interface's subnets
	    my $invalid_subnet = 1;
	    foreach my $nsub ( @{$devsubnets{$intid}} ){
		my $nip = NetAddr::IP->new($ip) 
		    || $self->throw_fatal(sprintf("Cannot create NetAddr::IP object from %s", $ip));
		if ( $nip->within($nsub) ){
		    $invalid_subnet = 0;
		    last;
		}else{
		    $logger->debug(sub{sprintf("Device::CLI::FoundryIW::_get_arp_from_cli: $host: IP $ip not within %s", 
					       $nsub->cidr)});
		}
	    }
	    if ( $invalid_subnet ){
		$logger->debug(sub{"Device::CLI::FoundryIW::_get_arp_from_cli: $host: IP $ip not within interface $iname subnets"});
		next;
	    }
	}

	# Store in hash
	$cache{$intid}{$ip} = $mac;
	$logger->debug(sub{"Device::CLI::FoundryIW::_get_arp_from_cli: $host: $iname -> $ip -> $mac" });
    }
    
    return \%cache;
}



############################################################################
#_get_fwt_from_cli - Fetch forwarding tables via CLI
#
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#    
#   Examples:
#     $self->_get_fwt_from_cli();
#
#
sub _get_fwt_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_fwt_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);
    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show mac-address', personality=>'foundry');

    # MAP interface names to IDs
    my %int_names;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
    }

    my ($iname, $mac, $intid, $vlan);
    my %fwt;
    
    foreach my $line ( @output ) {
	chomp($line);
	if ( $line =~ /^(\w{4}\.\w{4}\.\w{4})\s+(\S+)\s+\d+\s+(\d+)\s+/ ) { # MLX Syntax
	    # Output look like this:
	    # MAC Address     Port      Age      VLAN    Type
	    # 0040.95d1.3828   2/7        0       177
	    # 0050.568b.001e   1/6      120        27
	    $mac   = $1;
	    $iname = $2;
	    $vlan  = $3;
	}elsif ( $line =~ /^(\w{4}\.\w{4}\.\w{4})\s+(\S+)\s+\S+\s+\d+\s+(\d+)\s+/ ) { # FastIron SX GS/LS/WS Syntax
	    # Output look like this:
	    # MAC-Address     Port           Type          Index  VLAN 
	    # d89e.3fb9.1107  0/1/3          Dynamic       8829   144  
	    # 0022.41fc.3713  0/1/3          Dynamic       10356  135  
	    $mac   = $1;
	    $iname = $2;
	    $vlan  = $3;
	}elsif ( $line =~ /^(\w{4}\.\w{4}\.\w{4})\s+(\d+)\s+\S+\s+(\d+)\s+/ ) { # Turboiron 24X Syntax
	    # Output look like this:
	    # MAC-Address     Port           Type         VLAN 
	    # d89e.3fb9.1107  24             Dynamic      144  
	    # 0022.41fc.3713  24             Dynamic      135  
	    $mac   = $1;
	    $iname = $2;
	    $vlan  = $3;
	} else {
	    $logger->debug(sub{"Device::CLI::FoundryIW::_get_fwt_from_cli: line did not match criteria: $line" });
	    next;
	}
	$iname = $self->_reduce_iname($iname);
	my $intid = $int_names{$iname};

	unless ( $intid ) {
	    $logger->warn("Device::CLI::FoundryIW::_get_fwt_from_cli: $host: Could not match $iname to any interface names");
	    next;
	}
	
	my $validmac = PhysAddr->validate($mac);
	if ( $validmac ){
	    $mac = $validmac;
	}else{
	    $logger->debug(sub{"Device::CLI::FoundryIW::_get_fwt_from_cli: $host: Invalid MAC: $mac" });
	    next;
	}	

	# Store in hash
	$fwt{$intid}{$mac} = 1;
	$logger->debug(sub{"Device::CLI::FoundryIW::_get_fwt_from_cli: $host: $iname -> $mac" });
    }
    
    return \%fwt;
}


############################################################################
# _reduce_iname
#  Convert "*Ethernet0/1/2 into "0/1/2" to match the different formats
#
# Arguments: 
#   string
# Returns:
#   string
#
sub _reduce_iname{
    my ($self, $name) = @_;
    return unless $name;
    $name =~ s/^.*Ethernet//;
    return $name;
}

=head1 AUTHOR

Vincent Magnin <vincent.magnin at unil.ch>

=head1 COPYRIGHT & LICENSE

Copyright 2012 Vincent Magnin 

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

#Be sure to return 1
1;
