#!/usr/bin/perl

# Generate grep'able contact info files from Netdot
# 
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Data::Dumper;
use Getopt::Long;

use vars qw( %self $USAGE @cls );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --dir <DIR> --out <FILE>

    --dir             <path> Path to configuration file
    --out             <name> Configuration file name (default: $self{out})
    --debug           Print debugging output
    --help            Display this message

EOF

&setup();
&gather_data();
&build_configs();


##################################################
sub set_defaults {
    %self = ( 
	      dir             => '',
	      out             => 'contacts.txt',
	      help            => 0,
	      debug           => 0, 
	      );

}

##################################################
sub setup{
    
    my $result = GetOptions( 
			     "dir=s"            => \$self{dir},
			     "out=s"            => \$self{out},
			     "debug"            => \$self{debug},
			     "h"                => \$self{help},
			     "help"             => \$self{help},
			     );
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }

    unless ( $self{dir} && $self{out} ) {
	print "ERROR: Missing required arguments\n";
	die $USAGE;
    }
}


##################################################
sub gather_data{
   
    unless ( @cls = sort { $a->name cmp $b->name } ContactList->retrieve_all ){
	exit 0;
    }
    
}

##################################################
sub build_configs{

    my $filename = "$self{dir}/$self{out}";
    open (FILE, ">$filename") 
	or die "Couldn't open $filename: $!\n";
    
    print FILE "            ****        THIS FILE WAS GENERATED FROM A DATABASE         ****\n";
    print FILE "            ****           ANY CHANGES YOU MAKE WILL BE LOST            ****\n\n";
    
    foreach my $cl ( @cls ){
	my @sites    = $cl->sites;
	my @entities = $cl->entities;
	my @contacts = $cl->contacts;
	my @people   = map { $_->person } @contacts;
	my @people   = sort { $a->lastname cmp $b->lastname } @people;
	
	foreach my $site (@sites){
	    my $prefix = $site->name;
	    &print_people($prefix, \@people);
	}
	foreach my $ent (@entities) {
	    my $prefix = $ent->name;
	    &print_people($prefix, \@people);
	}
    }
    close (FILE) or warn "$filename did not close nicely\n";
}

##################################################
sub print_people {
    my ($prefix, $people) = @_;
    foreach my $person ( @$people ){
	my $pref = $prefix;
	$pref .= ": " . $person->firstname . " " . $person->lastname;
	print FILE $pref, ": Employer: ",    $person->entity->name, "\n"  if ($person->entity);
	print FILE $pref, ": Position: ",    $person->position,     "\n"  if ($person->position);
	print FILE $pref, ": Office: ",      $person->office,       "\n"  if ($person->office);
	print FILE $pref, ": Email: <",      $person->email,        ">\n" if ($person->email);
	print FILE $pref, ": Cell: ",        $person->cell,         "\n"  if ($person->cell);
	print FILE $pref, ": Pager: ",       $person->pager,        "\n"  if ($person->pager);
	print FILE $pref, ": Email-Pager: ", $person->emailpager,   "\n"  if ($person->emailpager);
    }
    print FILE "\n";
}
