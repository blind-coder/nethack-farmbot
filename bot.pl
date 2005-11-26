#!/usr/bin/perl -w
use strict;
use Fcntl;
use IO::Select;
use IPC::Open2;
use Time::HiRes;

# config start
my $username="wizard"; # the name of your avatar
my $autouser="wizard"; # your login. leave blank to not log in automatically
my $autopass="wizard"; # your password
my $server="ceres";    # the server name or ip address
my $port="telnet";     # the server port to connect to

my $god = "chaotic";   # your god. may be name or alignment
my $waytochest = "h";  # which way to go to the chest
my $waytoaltar = "l";  # which way to go to the altar. opposite of chest
my $chestname = "FILLME"; # chestname

my $weapon = "a";      # inventory slot your puddingbane is in
my $stethoscope = "s"; # inventory slot your stethoscope is in

my $dosacrifice = 1;   # 1 = sacrifice puddings, 0 = do not sacrifice
my $dopray = 1;   # 1 = pray when safe, 0 = don't

my $debug = 0;         # leave this off
my $status = 1;        # turn this off if you're having display issues.
# config end

my @queue;

my $val;
my $rin;
my $nfound;
my $rout;
my $key;
my $numhit = 0;
my $running = 0;
my $nhmessage = "";
my $nomonstturn = 0;
my $read;
my $lasttime = 0;
my $hungry = 0;
my $monsterskilled = 0;
my $totalmonsterskilled = 0;
my $cleanup = 0; # XXX doesn't really work yet
my $movetarget = "";
my $praysafe = 0;
my $waitingforinput = 0;

my $sacrifices = "0";
my $splits = "0";
my $gifts = "0";
my $protection = "0";
my $goldenglow = "0";
sub updatestatus {
	return unless $status;
	my $statusline = "Kil: $totalmonsterskilled Spl: $splits Sac: $sacrifices Gi: $gifts Pr: $protection Fh: $goldenglow " . 
	($praysafe && "[Can pray] " || "") . 
	($movetarget && "Target: $movetarget"); 
  print "[s";     #save position
  print "[25;0H"; #cursor to bottom left
  print "[K";     #erase the line
  print $statusline;
  print "[u";     #return cursor back to where it saved
        }

sub readfromnethack { # {{{
	$nfound = select($rout=$rin, undef, undef, 0);
	$key="";
	if (vec($rout, fileno(NETHACK), 1)){
		sysread(NETHACK, $key, 1);
		return 1;
	}
	return 0;
} #  }}}
sub debug { #{{{
	return unless $debug;
	my $line=shift;
	print STDERR $line."\n";
	1;
} # }}}
sub sendnow {#{{{
	my $send=shift;
	debug "sending: '$send'";
	print NETCAT "$send";
	1;
}#}}}
sub addcommand {#{{{
	my $command = shift;
	if ($running){
		push @queue, $command;
	} else {
		undef(@queue);
	}
	1;
}#}}}
sub runcommand {#{{{
	if ($running and defined($queue[0])){
		my @tmp; my $first;
		sendnow $queue[0];
		$first = 1;
		foreach my $val (@queue){
			unless ($first){
				push @tmp, $val;
			}
			$first=0;

	updatestatus;
		}
		@queue=@tmp;
	} else {
		undef(@queue);
	}

}#}}}
sub pickup {#{{{
	my $pickedup=0;
	my $pickmeup=shift;
	my $number=shift;
	my $breakloop=0;
	my $pickupnow;
	my $pickupletters;
	$pickupletters="\\";
	$pickupnow=0;
	if (!$number){
		$number=999999999; # will probably never be reached unless polymorphed into a nymph
	}
	$nhmessage="";

	sendnow ",";
	debug "trying to pick up $pickmeup";
	while (1){
		$nhmessage.=$key if readfromnethack;
		debug "pickup: nhmessage is: $nhmessage";
		print STDOUT "$key";
		if ($nhmessage =~ /--More--/){
			$breakloop++;
		}
		if ($breakloop > 5000){
			debug "uh-oh. We're hanging somewhere. Trying to break free.";
			sendnow ",";
			$breakloop=0;
			$nhmessage="";
			next;
		}
		if ($nhmessage eq "There is nothing here to pick up."){
			$nhmessage="";
			return 1;
		}
		if ($nhmessage =~ /Pick up what/){
			$pickupnow=1;
			$nhmessage="";
			next;
		}
		if (!$pickupnow){
			if ($nhmessage=~//){
				$nhmessage=~s/^.*(.*)/$1/;
			}
			next;
		}
		if ($nhmessage =~ /([a-zA-Z]) \+ (.*)/){
			my $letter; my $item;
			$letter=$1;
			$item=$2;
			if ($item !~ /$pickmeup/){
				debug "pickup: somehow '$item' got activated. deselecting.";
				sendnow $letter;
			}
			
		}
		if ($nhmessage =~ /([a-zA-Z]) - (.*)/){
			my $letter; my $item;
			$letter=$1;
			$item=$2;
			if ($item =~ /$pickmeup/ and $item !~ /loadstone/ and $number > 0){
				my $amount;
				my $howmany;
				$howmany="";
				debug "picking up $letter - $item";
				$item=~/^([anthe0-9]+) .*/;
				$amount=$1;
				if ($amount eq "a" or $amount eq "an" or $amount eq "the"){
					$amount=1;
				}
				$number-=$amount;
				if ($number < 0){
					$howmany=$amount+$number;
				}
				$pickupletters.="$howmany$letter";
				$pickedup=1;
			}
			$nhmessage="";
		}
		if ($nhmessage =~ /\(([0-9]+) of ([0-9]+)\)/){
			debug "pickup: matched: $1 - $2";
			sendnow "$pickupletters ";
			$pickupletters="\\";
			$nhmessage="";
			if ($1 == $2){
				return $pickedup;
			}
			if ($number <= 0){
				sendnow "";
				$pickupletters="\\";
				return $pickedup;
			}
			if ($pickmeup eq "." and $pickedup){
				sendnow "";
				$pickupletters="\\";
				return $pickedup;
			}
		}
		if ($nhmessage =~ /\(end\)/){
			debug "pickup: end of listing";
			sendnow "$pickupletters ";
			$pickupletters="\\";
			return $pickedup;
		}
		if ($nhmessage =~ /You have.*trouble/){
			$nhmessage=0;
			debug "pickup: weight problems";
			sendnow "q";
			return $pickedup;
		}
	}
}#}}}
sub putin {#{{{
	my $pickedup=0;
	my $pickmeup=shift;
	$nhmessage="";

	print STDERR "trying to put in $pickmeup";
	while (1){
		$nhmessage.=$key if readfromnethack;
		debug "putin: nhmessage is: $nhmessage";
		print STDOUT "$key";
		if ($nhmessage =~ /--More--/){
			sendnow " ";
			$nhmessage="";
			next;
		}
		if ($nhmessage =~ /([a-zA-Z]) \+ (.*)/){
			my $letter; my $item;
			$letter=$1;
			$item=$2;
			if ($letter eq $stethoscope or $letter eq $weapon or $item =~ /(corpse|large box|chest)/){
				debug "putin: somehow '$item' got activated. deselecting.";
				sendnow $letter;
			}
			
		}
		if ($nhmessage =~ /([a-zA-Z]) - (.*)/){
			my $letter; my $item;
			$letter=$1;
			$item=$2;
			if ($item =~ /$pickmeup/ and not ($letter eq $stethoscope or $letter eq $weapon or $item =~ /(corpse|large box|chest)/)){
				sendnow "$letter";
				debug "putting in $letter - $item";
				$pickedup=1;
			}
			$nhmessage="";
		}
		if ($nhmessage =~ /\(([0-9]+) of ([0-9]+)\)/){
			debug "putin: matched: $1 - $2";
			sendnow " ";
			$nhmessage="";
			if ($1 == $2){
				return $pickedup;
			}
		}
		if ($nhmessage =~ /\(end\)/ and $nhmessage !~ /$chestname/){
			debug "putin: end of inventory";
			sendnow " ";
			$nhmessage="";
			return $pickedup;
		}
	}
}#}}}
sub onaltar {#{{{
	$movetarget="";
	if ($nomonstturn > 50){
		if (!pickup "scare monster"){
			debug "Don't know why monsters ceased. SHUTTING DOWN";
			$running=0;
		} else {
			sendnow "";
			undef(@queue);
			$movetarget = "Elbereth";
		}
		debug "altar resetting nomonstturn.";
		$nomonstturn=0;
	}
	if ($hungry){
		if (pickup "(food ration|gunyoki)", 5){
			sendnow "";
			undef(@queue);
			$movetarget="Elbereth";
		} else {
			$running=0;
			debug "No food on altar and hungry. SHUTTING DOWN";
		}
	}
	if ($monsterskilled > 5){
		debug "starting to sac";
		$movetarget = "#offer";
	}
	if ($cleanup){
		if (pickup "."){
			sendnow "";
			undef(@queue);
			$movetarget="Elbereth";
		} else {
			debug "couldn't pick up anything.";
			$cleanup=0;
			$movetarget="Elbereth";
		}
	}
}#}}}
sub onElbereth {#{{{
	if ($hungry){
		addcommand "e";
		$waitingforinput=0;
	}
	if ($movetarget eq "Elbereth"){
		$movetarget="";
		$waitingforinput=0;
	}

}#}}}
sub move {#{{{
	debug "start a movement for '$movetarget'";
	if ($movetarget eq "Elbereth"){
		return ($waytochest);
	}
	if ($movetarget eq "altar"){
		return ($waytoaltar);
	}
	if ($movetarget eq "eat"){
		return ("e");
	}
	if ($movetarget eq "loot"){
		return ("#loot");
	}
	if ($movetarget eq "#offer"){
		return "ï";
	}
	if ($movetarget eq "#pray"){
		return "ð";
	}
	return 0;
}#}}}
sub throw { #{{{
	my $what=shift;
	my $where=shift;
	my $throwno;
	$throwno=0;
	sendnow "t*";
	$nhmessage="";
	debug "trying to throw $what to $where";
	while (1){
		$nhmessage.=$key if readfromnethack;
		debug "throw: nhmessage is: $nhmessage";
		print STDOUT "$key";
		if ($nhmessage =~ /want to throw/){
			$throwno=1;
			$nhmessage="";
			next;
		}
		if (!$throwno){
			if ($nhmessage=~//){
				$nhmessage=~s/^.*(.*)/$1/;
			}
			next;
		}
		if ($nhmessage =~ /(.) - (.*)/){
			my $letter; my $item;
			$letter=$1;
			$item=$2;
			if ($item =~ $what){
				sendnow "$letter$where";
				return 1;
			}
			$nhmessage="";
		}
		if ($nhmessage =~ /\(([0-9]+) of ([0-9]+)\)/){
			debug "throw: matched: $1 - $2";
			sendnow " ";
			$nhmessage="";
			if ($1 == $2){
				return 0;
			}
		}
		if ($nhmessage =~ /\(end\)/){
			debug "throw: end of inventory";
			sendnow " ";
			$nhmessage="";
			return 0;
		}
	}
} #}}}
sub act {#{{{
	for ($nhmessage){
		if (/--More--/){
			debug "got --More--";
			sendnow " ";
			$waitingforinput=0;
			$nhmessage=~s/--More--//g;
		}
		if (/To what position do you want to be teleported/){
			debug "got teleport prompt";
			sendnow " .";
			$nhmessage="";
			next;
		}
		if (/You hit/){
			$nomonstturn=0;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/Wait!.*There's (.*) hiding under/){
			$nhmessage="";
			$waitingforinput=0;
			debug "whoops, a $1 was ambushing us";
			next;
		}
		if (/You kill.*(brown|black)/){
			$nomonstturn=0;
			$nhmessage="";
			$waitingforinput=0;
			$monsterskilled++;
			$totalmonsterskilled++;
			next unless $dosacrifice;
			debug "We killed $monsterskilled now";
			if ($monsterskilled > 5){
				$movetarget="altar";
				debug "going to sacfest now";
			}
			next;
		}
		if (/You (kill|destroy).*/){
			$nomonstturn=0;
			$nhmessage="";
			$waitingforinput=0;
			debug "We killed something else than a pudding";
			next;
		}
		if (/attack thin air/){
			$nomonstturn++;
			if ($nomonstturn > 50){
				debug "No monster for a long time.";
				$movetarget="altar";
			}
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/divides as you/){
			$nomonstturn=0;
			$splits++;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/You strike the .* from behind!/){
			$nomonstturn=0;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/altar.*$god/){
			debug "on the altar";
			onaltar;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/What do you want to name/){
			sendnow "\n";
			$waitingforinput=0;
			$nhmessage="";
			next;
		}
		if (/Call a/){
			sendnow "\n";
			$waitingforinput=0;
			$nhmessage="";
			next;
		}
		if (/reconciliation/){
			debug "safe to pray";
			$nhmessage="";
			$praysafe=999 if $dopray==1;
			$waitingforinput=0;
			next;
		}
		#Change by Cyde Weys 2005-07-01
		#If you are a vampire lord then the effect of your
		#bite attack is: "<enemy> seems weaker."  This wasn't
		#previously handled and caused the bot to bail out.
		if (/(?:bites|seems weaker)/){
			$numhit++;
			$nhmessage="";
			next;
		}
		if (/Status.*$username.*HP *([0-9]+)\(([0-9]+)\)/){
			debug "HP: $1 Max: $2";
			$nhmessage="";
			if ($1 < 20 or $1 < $2 / 7){
				debug "We should heal";
				$running=0;
				debug "SHUTTING DOWN";
			}
			next;
		}
		if (/[Hh]ungry/){
			if ($movetarget eq ""){
				undef (@queue);
				$nhmessage="";
				debug "We're getting hungry.";
				$movetarget="eat";
				next;
			}
		}
		if (/You don't have anything to eat/){
			# only happens from above
			$hungry=1;
			$nhmessage="";
			$movetarget="altar";
			$waitingforinput=0;
			debug "Trying to get food from altar.";
			next;
		}
		if (/(You finish eating|This.*bland|This.*tastes.*terrible)/){
			$hungry=0;
			$nhmessage="";
			$waitingforinput=0;
			debug "done eating";
			next;
		}
		if (/What.*engrave.*with/){
			debug "Whoops, what happened?";
			$running=0;
			$nhmessage="";
			next;
		}
		if (/There (is|are) (.*) here.*eat/){
			debug "eating $2 from the floor is bad for your health.";
			undef (@queue);
			sendnow "n";
			$nhmessage="";
			next;
		}
		if (/There (is|are) ([an0-9]*) (brown|black) pudding corpse.*sacrifice/){
			debug "saccing $2 $3 pudding";
			sendnow "y";
			$waitingforinput=1;
			$nhmessage="";
			next;
		}
		if (/There (is|are) (.* corpse).*sacrifice/){
			debug "Cowardly refusing to sacrifice $2";
			sendnow "n";
			$nhmessage="";
			$waitingforinput=1;
			next;
		}
		if (/What do you want to sacrifice/){
			debug "Refusing to sac from inventory";
			sendnow "";
			$nhmessage="";
			if ($movetarget eq "#offer"){
				$movetarget="Elbereth";
				$monsterskilled=0;
				$waitingforinput=0;
			}
			next;
		}
		if (/Your sacrifice is consumed/){
			$sacrifices++;
			debug "We sacced something";
			if ($movetarget eq "#offer"){
				$praysafe++ if $dopray==1;
				debug "incrementing praysafe to $praysafe";
				if ($praysafe > 3){
					debug "safe to pray. doing so";
					$movetarget="#pray";
					$praysafe=0;
				}
				$nhmessage="";
				$waitingforinput=0;
				next;
			}
		}
		if (/hopeful feeling/){
			debug "Not ready to pray yet";
			$praysafe=0;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/inadequacy/){
			debug "WHOOPS! Messed up praying. SHUTTING DOWN";
			$praysafe=0;
			$running=0;
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/voice.*(booms|rings|thunders)/){
			debug "Our god wants to tell us something";
			$praysafe=0;
			if ($movetarget eq "#pray"){
				$movetarget = "#offer";
			}
			$nhmessage="";
			$waitingforinput=0;
			next;
		}
		if (/reconciliation/){
			debug "We can safely pray :D";
			if ($movetarget eq "#offer"){
				$movetarget="#pray";
				$praysafe=0;
				$nhmessage="";
				$waitingforinput=0;
				next;
			}
		}
		if (/Are you sure you want to pray/){
			debug "prayconfirmation required";
			if ($movetarget eq "#pray"){
				debug "we are sure";
				sendnow "y";
				$waitingforinput=1;
			} else {
				debug "we'd rather not, thanks.";
				sendnow "n";
				$waitingforinput=0
			}
			$nhmessage="";
			next;
		}
		if (/Force the gods to be pleased/){
			debug "Wizmode! The Gods can't be forced";
			sendnow "n";
			$nhmessage="";
			next;
		}
		if (/Nothing happens/){
			debug "Nothing happened. Too bad";
			if ($movetarget eq "#offer"){
				my $corpsesleft;
				$corpsesleft=1;
				debug "Sacrifice too old";
				while ($corpsesleft){
					if (pickup "pudding corpse", 1){
						throw "pudding corpse", "$waytochest";
					} else {
						$corpsesleft=0;
					}
				}
				$nhmessage="";
				$movetarget="Elbereth";
				$monsterskilled=0;
				$waitingforinput=0;
				next;
			}
		}
		if (/You begin praying/){
			debug "We're praying, back to saccing";
			if ($movetarget eq "#pray"){
				$movetarget="#offer";
				$nhmessage="";
				$waitingforinput=1;
				next;
			}
		}
		if (/You don't have anything to sacrifice./){
			debug "Nothing to sac";
			$nhmessage="";
			if ($movetarget eq "#offer"){
				$movetarget="Elbereth";
				$monsterskilled=0;
				$waitingforinput=0;
			}
			next;
		}
		if (/There .* $chestname .*loot/){
			sendnow "y ia";
			if ($cleanup){
				putin ".";
				$movetarget="altar";
				$nhmessage="";
				next;
			}
		}
		if (/There.*loot/){
			sendnow "n";
			$nhmessage="";
			next;
		}
		if (/Stop eating/){
			sendnow "y";
			$hungry=0;
			debug "We almost choked";
			$nhmessage="";
			$movetarget = "" if $movetarget  eq "eat";
			next;
		}
		if (/What do you want to eat...(.)/){
			undef(@queue);
			sendnow "$1";
			$hungry=0;
			debug "We ate something";
			$nhmessage="";
			$movetarget = "" if $movetarget  eq "eat";
			next;
		}
		if (/(weak|fainting|stiff|You die|FoodPois)/i){
			if ($running){
				debug "uh-oh. EMERGENCY";
				$running=0;
			}
			$nhmessage="";
			next;
		}
		if (/Do you want to keep the save file/){
			debug "Wizmode: keepsave";
			sendnow "n";
			$nhmessage="";
			next;
		}
		if (/named $chestname/){
			if ($cleanup){
				debug "sending lootcommand";
				undef(@queue);
				$movetarget="loot";
				$nhmessage="";
				next;
			}
		}
		if (/Things that are here/){
			debug "Got a listing from the ground.";
			addcommand " ";
			$nhmessage="";
			next;
		}
		if (/Really attack the (.*?)\?/){
			debug "peaceful $1. killing it anyway";
			sendnow "y";
			$nhmessage="";
			next;
		}
		if (/but in vain/){
			debug "Something went wrong. We tried pushing a boulder.";
			$waitingforinput=0;
			$nhmessage="";
			next;
		}
		if (/You hear.*noises/){
			debug "Our pet is running wild.";
			$waitingforinput=0;
			$nhmessage="";
			next;
		}
		if (/Elbereth/){
			$nhmessage="";
			onElbereth;
			next;
		}
		if (/Use my gift wisely!/){
			$nhmessage="";
			$waitingforinput=0;
			$gifts++;
			next;
		}
		if (/my protection/) {
			$nhmessage="";
			$waitingforinput=0;
			$protection++;
			next;
		}
		if (/are surrounded by a golden glow/) {
			$nhmessage="";
			$waitingforinput=0;
			$goldenglow++;
			next;
		}
		$nhmessage=~s/^.*(.*)/$1/ if $nhmessage =~ //;
		
	}
}#}}}
# setup communication {{{
open2(*NETHACK, *NETCAT,  "telnet -8 $server $port");
select(NETCAT);
$|=1;
select(NETHACK);
$|=1;
select(STDIN);
$|=1;
system "stty -echo -icanon eol \001";
select(STDOUT);
$|=1;

$rin = '';
vec($rin, fileno(STDIN), 1) = 1;
vec($rin, fileno(NETHACK), 1) = 1;
# }}}

if ($autouser ne ""){
	sendnow "l".$autouser."\n".$autopass."\n";
}

while(1){
	$nfound = select($rout=$rin, undef, undef, 0);
	if ($nfound){
		if (vec($rout, fileno(STDIN), 1)){
			sysread(STDIN, $key, 1);
			sendnow "$key";
			if ($running){
				debug "user input. SHUTTING DOWN";
				$running=0;
			}
		}
		if (vec($rout, fileno(NETHACK), 1)){
			$read=0;
			while (readfromnethack){
				$nhmessage.=$key;
				print STDOUT "$key";
				$read++;
				last if $key eq "";
				last if $read>25;
			}
			debug "main: nhmessage: $nhmessage";
			if ($nhmessage =~ /start: unknown extended command/){
				debug "STARTING UP";
				$nhmessage="";
				$running = 1;
				$waitingforinput=0;
				next;
			}
			if ($nhmessage =~ /clean(.): unknown extended command/){
				my $what=$1;
				sendnow "$waytoaltar,$whatDX.,$what$waytochest#looty i$what .";
				$nhmessage="";
				$waitingforinput=0;
			}
			if (!$running){
				if ($nhmessage=~//){
					$nhmessage=~s/^.*(.*)/$1/;
				}
				next;
			}
			act;
			if ($numhit > 5){
				addcommand "a$stethoscope.";
				$numhit=0;
			}
		}
	} elsif ($running) {
		if (!$waitingforinput and not defined($queue[0])){
			debug "adding our own command";
			if (move){
				debug "adding command " . move;
				addcommand move;
				$waitingforinput=1;
			} else {
				debug "adding command F$waytoaltar";
				addcommand "F$waytoaltar";
				$waitingforinput=1;
			}
		}
		runcommand;
	}
}
