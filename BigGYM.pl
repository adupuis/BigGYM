#!/usr/bin/perl
use strict;
use warnings;
use POE;
use POE::Component::Client::DNS;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotCommand;
use Net::GitHub::V2::Issues;
use Getopt::Long;
use IO::File;
use Data::Dumper;
use IRC::Utils ':ALL';

my $token = 'fake';
my $login = 'superfake';
my $owner = 'adupuis';
my $repo = 'BigGYM';
my $log_file = 'BigGYM.log';
my $log_fh;
my $version = '0.08';
my $botname = 'BigGYM-'.$$;
my @channels = ('#genymobile');
my $default_project = 'adupuis/BigGYM';
my $last_commit = '';

print "== Starting BigGYM v$version ==\n";

GetOptions ("gh-login=s" => \$login,"gh-token=s" => \$token,"gh-owner=s" => \$owner,"gh-repo=s" => \$repo, "logfile=s" => \$log_file, "botname=s" => \$botname, "channel=s" => \@channels);

my $dns = POE::Component::Client::DNS->spawn();
my $irc = POE::Component::IRC->spawn(
    nick   => $botname,
    server => 'irc.freenode.net',
);

print "-- Openning log file: $log_file\n";

$log_fh = new IO::File;
$log_fh->open(">>$log_file") or die "Error: $!";
$log_fh->autoflush(1);

print "-- Writting PID\n";

open(my $fh, ">:encoding(UTF-8)", "BigGYM.pid") || die "can't open PID file: $!";
print $fh $$;
close($fh);

print "-- Connecting to GitHub\n";

my $issue = Net::GitHub::V2::Issues->new(
	owner => $owner, repo => $repo,
	login => $login, token => $token,
);

print "-- Starting POE session\n";

POE::Session->create(
    package_states => [
        main => [ qw(_start irc_001 irc_botcmd_slap irc_botcmd_lookup dns_response irc_botcmd_issue irc_botcmd_set_default_project irc_botcmd_list_issues irc_botcmd_reboot irc_botcmd_count_issues irc_botcmd_version irc_public) ],
    ],
);

$poe_kernel->run();

sub _start {
	print "-- Starting IRC session\n";
	$irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
		Commands => {
		slap                => 'Takes one argument: a nickname to slap.',
		lookup              => 'Takes two arguments: a record type (optional), and a host.',
		issue               => 'Takes two arguments: an issue number and an action (optionnal)',
		set_default_project => 'Takes one argument: the project name on GitHub (ex: adupuis/BigGYM)',
		list_issues         => 'Takes no argument. List all open issues for the default project',
		reboot              => 'Takes no argument. Restart the bot.',
		version             => 'Takes no argument. State the bot version number.',
		count_issues        => 'Takes no argument. State the number of opened issues in the default project.',
		}
	));
	$irc->yield(register => qw(001 botcmd_slap botcmd_lookup botcmd_issue botcmd_set_default_project botcmd_list_issues botcmd_reboot botcmd_count_issues botcmd_version public));
	print "-- Connecting to FreeNode\n";
	$irc->yield(connect => { });
}

# join some channels
sub irc_001 {
	print "-- $botname joins channels.\n";
	$irc->yield(join => $_) for @channels;
	my @greetings = ("Hi there, BigGYM is in da place !","BigGYM up & running.","Lock & load babe !","Not again...");
	srand (time ^ $$ ^ unpack "%L*", `ps axww | gzip -f`);
	$irc->yield(privmsg => $_ => $greetings[int(rand(scalar(@greetings)))]) for @channels;
	return;
}

# the good old slap
sub irc_botcmd_slap {
    my $nick = (split /!/, $_[ARG0])[0];
    my ($where, $arg) = @_[ARG1, ARG2];
    $irc->yield(ctcp => $where, "ACTION slaps $arg");
    return;
}

# version number
sub irc_botcmd_version {
    my $nick = (split /!/, $_[ARG0])[0];
    my ($where, $arg) = @_[ARG1, ARG2];
    $irc->yield(privmsg => $where, "BigGYM current version is ".BOLD."v".GREEN.$version.GREEN.BOLD);
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

sub irc_botcmd_reboot {
	my $nick = (split /!/, $_[ARG0])[0];
	my ($where, $arg) = @_[ARG1, ARG2];
	if($nick eq "Arno[Slack]"){
		system("./start_biggym.sh &");
	}
	else{
		$irc->yield(privmsg => $where, "Beau geste $nick ;-)");
	}
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
	$irc->yield(privmsg => $where, BOLD."---------------------------\n".BOLD);
	foreach my $iss (@{$issue->list('open')}){
		print Data::Dumper::Dumper($iss),"\n";
		my $body = $iss->{'body'};
		$body=~s/\n/ /g;
		$irc->yield(privmsg => $where, BOLD."Number: ".BOLD.$iss->{'number'}."\n");
		$irc->yield(privmsg => $where, BOLD."Title : ".BOLD.$iss->{'title'}."\n");
		$irc->yield(privmsg => $where, BOLD."Body  : ".BOLD.$body."\n");
		$irc->yield(privmsg => $where, BOLD."URL   : ".BOLD.$iss->{'html_url'}."\n");
		$irc->yield(privmsg => $where, BOLD."Tags  : ".BOLD.join(',',@{$iss->{'labels'}})."\n");
		$irc->yield(privmsg => $where, BOLD."---------------------------\n".BOLD);
	}
	return;
}

sub irc_botcmd_count_issues {
	my $nick = (split /!/, $_[ARG0])[0];
	my $where = $_[ARG1];
	my $count = scalar(@{$issue->list('open')});
	my $color = RED;
	if($count == 0){
		$color = GREEN;
	}
	elsif( $count < 5 ){
		$color = BLUE;
	}
	elsif( $count < 10 ){
		$color = ORANGE;
	}
	my $message = BOLD."There is currently ".$color."$count".$color.BOLD.BOLD." opened issues.".BOLD;
	$irc->yield(privmsg => $where, $message);
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
	print "DEBUG: who=$who\n";
	my ($nick,$mask) = split /!/, $who ;
	my $channel = $where->[0];
	$what = strip_color($what) if( has_color($what) );
	if( $what =~ /^.*#(\d+).*$/ ){
		$irc->yield(privmsg => $where, "issue ".BOLD.BLUE."$1".BLUE.BOLD." is at: https://github.com/$default_project/issues/$1");
	}
	elsif( $what =~ /fix_issue\(([^,]+),(\d+),([^)]+)\)/ ){ # This will match line like "fix_issue(adupuis/BigGYM,2,issue resolved)"
		print "DEBUG: Entering fix issue code\n";
		my $project = $1;
		my $issue_number = $2;
		my $dev_comment = $3;
		print "DEBUG: project=$project\n";
		print "DEBUG: issue_number=$issue_number\n";
		print "DEBUG: dev_comment=$dev_comment\n";
		if($nick =~ /^CIA/ && $mask =~ /cia\.atheme\.org/i){
			if( defined($last_commit) && $last_commit ){
				if($project ne $default_project && $project =~ /^([^\/]+)\/(.+)$/ ){
					print "DEBUG: project in fix_issue is not the same as default => changing default.\n";
					$irc->yield(privmsg => $where, "Default project changed to $project");
					$default_project = $project;
					$owner = $1;
					$repo = $2;
					print "DEBUG: new default project is $default_project\n";
					print "DEBUG: re-creating Net::GitHub object with owner=$owner and repo=$repo\n";
					print "DEBUG: login=$login token=$token\n";
					$issue = Net::GitHub::V2::Issues->new(
						owner => $owner, repo => $repo,
						login => $login, token => $token,
					);
				}
				my $comment = $issue->comment( $issue_number, "Issue fixed in commit [master $last_commit]\nDev comment is :\n$dev_comment\n\nIssue closed automatically by BigGYM." );
				$issue->close( $issue_number );
				$irc->yield(privmsg => $where, "Issue ".BOLD.BLUE."$issue_number".BLUE.BOLD." auto-closed with comment : ");
				foreach(split(/\n/,$comment->{'body'})){
					$irc->yield(privmsg => $where, $_);
				}
				$last_commit = undef;
			}
			else{
				$irc->yield(privmsg => $where, BOLD.ORANGE."No master commit detected, impossible to fix issues.".ORANGE.BOLD);
			}
		}
		else{
			$irc->yield(privmsg => $where, BOLD.ORANGE."CIA bots are the only one allowed to auto_close issues.".ORANGE.BOLD);
		}
	}
	elsif( $what =~ /master[^r]+r[^\w]*(\w+)/ ){ #dupuis master * rf70c21c / 
		print "Last commit set to: $1\n";
		$last_commit = $1;
	}
	elsif( my @matches = $what =~ /(w[arnig]*|i[nfo]*|a[nounce]*)\(([^\)]+)\)/g ){
		print Data::Dumper::Dumper(@matches),"\n";
		my $cmd = $1;
		my $msg = $2;
		my $coloured_message = '';
		for(my $k=0; $k <= $#matches; $k+=2){
			if( $matches[$k] =~ /^w[arnig]*/ ){
				$coloured_message .= RED.$matches[$k+1].RED;
			}
			elsif( $matches[$k] =~ /^i[nfo]*/ ){
				$coloured_message .= BLUE.$matches[$k+1].BLUE;
			}
			elsif( $matches[$k] =~ /^a[nounce]*/ ){
				$coloured_message .= GREEN.$matches[$k+1].GREEN;
			}
		}
		$irc->yield(privmsg => $where, BOLD.$coloured_message.BOLD) if($coloured_message ne '');
	}
	# Anyway, log what happen
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	print $log_fh "[$year-$mon-$mday"."T"."$hour:$min:$sec] {$channel} <$nick> $what\n";
     return;
 }
 
