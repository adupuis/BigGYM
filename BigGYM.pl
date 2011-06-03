#!/usr/bin/perl
use strict;
use warnings;
use POE;
use POE::Component::Client::DNS;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;
use Net::GitHub::V2::Issues;
use Getopt::Long;
use Data::Dumper;

my $token = 'fake';
my $login = 'superfake';
my $owner = 'adupuis';
my $repo = 'BigGYM';

GetOptions ("gh-login=s" => \$login,"gh-token=s" => \$token,"gh-owner=s" => \$owner,"gh-repo=s" => \$repo);

my @channels = ('#genymobile');
my $dns = POE::Component::Client::DNS->spawn();
my $irc = POE::Component::IRC->spawn(
    nick   => 'BigGYM',
    server => 'irc.freenode.net',
);

# State variables
my $default_project = 'adupuis/GYMActivity';
my $last_commit = '';

my $issue = Net::GitHub::V2::Issues->new(
	owner => $owner, repo => $repo,
	login => $login, token => $token,
);

POE::Session->create(
    package_states => [
        main => [ qw(_start irc_001 irc_botcmd_slap irc_botcmd_lookup dns_response irc_botcmd_issue irc_botcmd_set_default_project irc_botcmd_list_issues irc_public) ],
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
		list_issues => 'Takes no argument. List all open issues for the default project',
		}
	));
	$irc->yield(register => qw(001 botcmd_slap botcmd_lookup botcmd_issue botcmd_set_default_project botcmd_list_issues public));
	$irc->yield(connect => { });
}

# join some channels
sub irc_001 {
    $irc->yield(join => $_) for @channels;
    $irc->yield(privmsg => $_ => "Hi there, BigGYM is in da place !") for @channels;
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
	if($default_project =~ /^([^\/]+)\/(.+)$/){
		$owner = $1;
		$repo = $2;
		$issue = Net::GitHub::V2::Issues->new(
			owner => $owner, repo => $repo,
			login => $login, token => $token,
		);
	}
	$irc->yield(privmsg => $where, "Default project set to $default_project");
	return;
}

sub irc_botcmd_list_issues {
	my $nick = (split /!/, $_[ARG0])[0];
	my $where = $_[ARG1];
	$irc->yield(privmsg => $where, "---------------------------\n");
	foreach my $iss (@{$issue->list('open')}){
# 		print Data::Dumper::Dumper($iss),"\n";
		$irc->yield(privmsg => $where, "Number: ".$iss->{'number'}."\n");
		$irc->yield(privmsg => $where, "Title : ".$iss->{'title'}."\n");
		$irc->yield(privmsg => $where, "Body  : ".$iss->{'body'}."\n");
		$irc->yield(privmsg => $where, "URL   : ".$iss->{'html_url'}."\n");
		$irc->yield(privmsg => $where, "Tags  : ".join(',',@{$iss->{'labels'}})."\n");
		$irc->yield(privmsg => $where, "---------------------------\n");
	}
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
	if( $what =~ /^.*#(\d+).*$/ ){
		$irc->yield(privmsg => $where, "issue $1 is at: https://github.com/$default_project/issues/$1");
	}
	elsif( $what =~ /^fix_issue\(([^,]+),(\d+),([^)]+)\)$/ ){ # This will match line like "fix_issue(adupuis/BigGYM,2,issue resolved)"
		my $project = $1;
		my $issue_number = $2;
		my $dev_comment = $3;
		if($project ne $default_project && $project =~ /^([^\/]+)\/(.+)$/ ){
			$irc->yield(privmsg => $where, "Default project changed to $project");
			$default_project = $project;
			$owner = $1;
			$repo = $2;
			$issue = Net::GitHub::V2::Issues->new(
				owner => $owner, repo => $repo,
				login => $login, token => $token,
			);
		}
		my $comment = $issue->comment( $issue_number, "Issue fixed in commit [master $last_commit]\nDev comment is :\n$dev_comment\n\nIssue closed automatically by BigGYM." );
		$issue->close( $issue_number );
		$irc->yield(privmsg => $where, "Issue $issue_number auto-closed with comment : ".$comment->{'id'}." - ".$comment->{'body'});
	}
	elsif( $what =~ /^.*master \* ([^\s]+)\s.*$/ ){ #dupuis master * rf70c21c / 
		print "Last commit set to: $1\n";
		$last_commit = $1;
	}
     return;
 }
 