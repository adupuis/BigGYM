#!/usr/bin/perl
use strict;
use warnings;
use POE;
use POE::Component::Client::DNS;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;

my @channels = ('#infinityperl');
my $dns = POE::Component::Client::DNS->spawn();
my $irc = POE::Component::IRC->spawn(
    nick   => 'BigGYM',
    server => 'irc.freenode.net',
);

# State variables
my $default_project = 'adupuis/GYMActivity';

POE::Session->create(
    package_states => [
        main => [ qw(_start irc_001 irc_botcmd_slap irc_botcmd_lookup dns_response irc_botcmd_issue irc_botcmd_set_default_project irc_public) ],
    ],
);

$poe_kernel->run();

sub _start {
	$irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
		Commands => {
		slap   => 'Takes one argument: a nickname to slap.',
		lookup => 'Takes two arguments: a record type (optional), and a host.',
		issue  => 'Takes two arguments: an issue number and an action (optionnal)',
		set_default_project => 'Takes one argument: the project name on GitHub (ex: adupuis/BigGYM)',
		}
	));
	$irc->yield(register => qw(001 botcmd_slap botcmd_lookup botcmd_issue botcmd_set_default_project public));
	$irc->yield(connect => { });
}

# join some channels
sub irc_001 {
    $irc->yield(join => $_) for @channels;
    return;
}

# the good old slap
sub irc_botcmd_slap {
    my $nick = (split /!/, $_[ARG0])[0];
    my ($where, $arg) = @_[ARG1, ARG2];
    $irc->yield(ctcp => $where, "ACTION slaps $arg");
    return;
}

# non-blocking dns lookup
sub irc_botcmd_lookup {
    my $nick = (split /!/, $_[ARG0])[0];
    my ($where, $arg) = @_[ARG1, ARG2];
    my ($type, $host) = $arg =~ /^(?:(\w+) )?(\S+)/;

    my $res = $dns->resolve(
        event => 'dns_response',
        host => $host,
        type => $type,
        context => {
            where => $where,
            nick  => $nick,
        },
    );
    $poe_kernel->yield(dns_response => $res) if $res;
    return;
}

sub irc_botcmd_issue {
	my $nick = (split /!/, $_[ARG0])[0];
	my ($where, $arg) = @_[ARG1, ARG2];
	print "DEBUG: $where => $arg\n";
	$irc->yield(privmsg => $where, "issue $arg is at: https://github.com/$default_project/issues/$arg");
	return;
}

sub irc_botcmd_set_default_project {
	my $nick = (split /!/, $_[ARG0])[0];
	my ($where, $arg) = @_[ARG1, ARG2];
	print "DEBUG: $where => $arg\n";
	$default_project = $arg;
	$irc->yield(privmsg => $where, "Default project set to $default_project");
	return;
}

sub dns_response {
    my $res = $_[ARG0];
    my @answers = map { $_->rdatastr } $res->{response}->answer() if $res->{response};

    $irc->yield(
        'notice',
        $res->{context}->{where},
        $res->{context}->{nick} . (@answers
            ? ": @answers"
            : ': no answers for "' . $res->{host} . '"')
    );

    return;
}

sub irc_public {
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
	my $nick = ( split /!/, $who )[0];
	my $channel = $where->[0];
		print "DEBUG: We are in public with $sender, $nick, $channel,$what\n";
	if ( my ($rot13) = $what =~ /^rot13 (.+)/ ) {
		$rot13 =~ tr[a-zA-Z][n-za-mN-ZA-M];
		$irc->yield( privmsg => $channel => "$nick: $rot13" );
	}
	elsif( $what =~ /^.*#(\d+).*$/ ){
		$irc->yield(privmsg => $where, "issue $1 is at: https://github.com/$default_project/issues/$1");
	}
     return;
 }
 