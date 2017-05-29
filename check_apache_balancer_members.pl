#!/usr/bin/perl
use strict;
use warnings;
use LWP::Simple;
use Data::Dump qw(dump);    #libdata-dump-perl
use Web::Scraper;           #libweb-scraper-perl

sub load_module {
    my @names = @_;
    my $module;
    for my $name (@names) {
        my $file = $name;
        # requires need either a bare word or a file name
        $file =~ s{::}{/}gsxm;
        $file .= '.pm';
        eval {
            require $file;
            $name->import();
            $module = $name;
		};
		last if $module;
    }
    return $module;
}

my $plugin_module;

$plugin_module = load_module( 'Monitoring::Plugin', 'Nagios::Plugin' ); #libmonitoring-plugin-perl or libnagios-plugin-perl

my $np = $plugin_module->new(
    usage => '',
    plugin => $0,
    shortname => "Balancer Members",
    blurb => 'Apache 2 Load Balancer Manager Members',
    timeout => 10
);

$np->add_arg(
    spec => 'hostname|h=s',
    help => 'hostname of the apache server',
    required => 1
);

$np->add_arg(
    spec => 'path|p=s',
    help => 'path to the balancer url',
    required => 1
);

$np->getopts;

my $response = get("http://".$np->opts->hostname."/".$np->opts->path);
my $s = scraper {
    process 'table:nth-of-type(2) tr:not(:first-child)', 'members[]' => scraper {
        process 'td:nth-of-type(1)', 'worker' => 'TEXT';
        process 'td:nth-of-type(6)', 'status' => 'TEXT';
        process 'td:nth-of-type(7)', 'elected' => 'TEXT';
        process 'td:nth-of-type(8)', 'to' => 'TEXT';
        process 'td:nth-of-type(9)', 'from' => 'TEXT';
    }
};

my $results = $s->scrape($response);

my @problemMembers = ();
my $at_least_one_is_ok = 0;

foreach my $member (@{$results->{'members'}})
{
    push @problemMembers, $member->{'worker'} if $member->{'status'} =~ /Err/i;
    $at_least_one_is_ok = 1 if $member->{'status'} =~ /Ok\s?$/;
}

$np->nagios_exit('CRITICAL', "No members are Ok; there is a problem") unless $at_least_one_is_ok;
$np->nagios_exit('CRITICAL', "Members have errors: " . join (", ", @problemMembers)) if (@problemMembers > 0);
$np->nagios_exit('OK', "All members functioning correctly");
