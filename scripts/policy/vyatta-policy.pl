#!/usr/bin/perl
use strict;
use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Misc;
use Getopt::Long;

my $VTYSH = '/usr/bin/vtysh';
my $ACL_CONSUMERS_DIR = "/opt/vyatta/sbin/policy";

my ( $accesslist, $accesslist6, $aspathlist, $communitylist, $extcommunitylist, $peer );
my ( $routemap, $deleteroutemap, $listpolicy );

GetOptions(
    "update-access-list=s"           => \$accesslist,
    "update-access-list6=s"          => \$accesslist6,
    "update-aspath-list=s"           => \$aspathlist,
    "update-community-list=s"        => \$communitylist,
    "update-extcommunity-list=s"     => \$extcommunitylist,
    "check-peer-syntax=s"            => \$peer,
    "check-routemap-action=s"        => \$routemap,
    "check-delete-routemap-action=s" => \$deleteroutemap,
    "list-policy=s"		     => \$listpolicy,
) or exit 1;

update_access_list($accesslist)               if ($accesslist);
update_access_list6($accesslist6)             if ($accesslist6);
update_as_path($aspathlist)                   if ($aspathlist);
update_community_list($communitylist)         if ($communitylist);
update_ext_community_list($extcommunitylist)         if ($extcommunitylist);
check_peer_syntax($peer)                      if ($peer);
check_routemap_action($routemap)              if ($routemap);
check_delete_routemap_action($deleteroutemap) if ($deleteroutemap);
list_policy($listpolicy)	    	      if ($listpolicy);

exit 0;

sub numerically { $a <=> $b; }

sub check_peer_syntax {
    my $peer = shift;

    $_ = $peer;
    if (/^local$/) { exit 0; }
    if ( isIpAddress("$peer") ) { exit 0; }
    exit 1;
}

sub is_community_list {
    my $list = shift;

    my $count = `$VTYSH -c \"show ip community-list $list\" | grep -c $list`;
    if ( $count > 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub is_extcommunity_list {
    my $list = shift;

    my $count = `$VTYSH -c \"show ip extcommunity-list $list\" | grep -c $list`;
    if ( $count > 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}


sub update_ext_community_list {
    my $variant= shift;
    my $name    = shift;
    my $config = new Vyatta::Config;
    my @rules  = ();

    if($variant !~ /^standard|expanded$/ ) { 
       die 
"set policy route extcommunity-list [ standard | expanded ] list-name rule rule-num action { deny | permit } 
                                   ^^^^^^^^^^^^^^^^^^^^^^^\n";
    };
    my  $cmdline="$VTYSH -c \"configure terminal\" ";
    # remove the old rule
    if ( is_extcommunity_list($name) ) {
        $cmdline.= " -c \"no ip extcommunity-list $name\" ";
    };

    $config->setLevel("policy route extcommunity-list $variant $name ");
    @rules = $config->listNodes();
    foreach my $rule ( sort numerically @rules ) {

        # set the action
        my $action = $config->returnValue("$rule action");
        die
          "policy route extcommunity-list $variant $name rule $rule: You must specify an action\n"
          unless $action;

        # grab the regex
        my $regex = $config->returnValue("$rule regex");
        die "policy route extcommunity-list $variant $name rule $rule: You must specify a regex\n"
          unless $regex;
        if($variant eq 'standard') {
           unless (($regex =~ /(.*):(.*)/) and (isIpAddress($1)or($1=~/^\d+$/) ) and ($2=~/^\d+$/)) {
              die "for standard extcommunity-list regex should be either:

AS:VAL

    This is a format to define AS based Extended Community value. AS part is 2 octets Global Administrator subfield in Extended Community value. VAL part is 4 octets Local Administrator subfield. 7675:100 represents AS 7675 policy value 100. 

IP-Address:VAL

    This is a format to define IP address based Extended Community value. IP-Address part is 4 octets Global Administrator subfield. VAL part is 2 octets Local Administrator subfield. 10.0.0.1:100 represents IP 10.0.0.1 policy value 100.
";
 
           };
        };
        $cmdline.="-c \"ip extcommunity-list $name $action $regex\" ";
    };
    exit system($cmdline);
}


sub update_community_list {
    my $num    = shift;
    my $config = new Vyatta::Config;
    my @rules  = ();

    # remove the old rule
    if ( is_community_list($num) ) {
        system(
            "$VTYSH -c \"configure terminal\" -c \"no ip community-list $num\" "
        );
    }

    $config->setLevel("policy community-list $num rule");
    @rules = $config->listNodes();

    foreach my $rule ( sort numerically @rules ) {

        # set the action
        my $action = $config->returnValue("$rule action");
        die
          "policy community-list $num rule $rule: You must specify an action\n"
          unless $action;

        # grab the regex
        my $regex = $config->returnValue("$rule regex");
        die "policy community-list $num rule $rule: You must specify a regex\n"
          unless $regex;

        system(
"$VTYSH -c \"configure terminal\" -c \"ip community-list $num $action $regex\" "
        );
    }

    exit 0;
}

sub is_as_path_list {
    my $list = shift;

    my $count =
      `$VTYSH -c \"show ip as-path-access-list $list\" | grep -c $list`;
    if ( $count > 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub update_as_path {
    my $word   = shift;
    my $config = new Vyatta::Config;
    my @rules  = ();

    # remove the old rule
    if ( is_as_path_list($word) ) {
        system(
"$VTYSH -c \"configure terminal\" -c \"no ip as-path access-list $word\" "
        );
    }

    $config->setLevel("policy as-path-list $word rule");
    @rules = $config->listNodes();

    foreach my $rule ( sort numerically @rules ) {

        # set the action
        my $action = $config->returnValue("$rule action");
        die "policy as-path-list $word rule $rule: You must specify an action\n"
          unless $action;

        # grab the regex
        my $regex = $config->returnValue("$rule regex");
        die "policy as-path-list $word rule $rule: You must specify a regex\n"
          unless $regex;

        system(
"$VTYSH -c \"configure terminal\" -c \"ip as-path access-list $word $action $regex\" "
        );
    }

    exit 0;
}

sub is_access_list {
    my $list  = shift;
    my $count = `$VTYSH -c \"show ip access-list $list\" | grep -c $list`;
    return ( $count > 0 );
}

sub is_access_list6 {
    my $list  = shift;
    my $count = `$VTYSH -c \"show ipv6 access-list $list\" | grep -c $list`;
    return ( $count > 0 );
}

sub notify_all_acl_consumers {
    my $args_string = shift;
    opendir (DIR, $ACL_CONSUMERS_DIR) or die "Could not open directory: $!";
    while (my $file = readdir DIR) {
      next if (-d "$ACL_CONSUMERS_DIR/$file");
      my $target = "$ACL_CONSUMERS_DIR/$file";
      if (-l "$ACL_CONSUMERS_DIR/$file") {
         my $target = readlink "$ACL_CONSUMERS_DIR/$file";
      } 
      system ("sudo $target $args_string");
    }
    closedir (DIR);
}

sub update_access_list {
    my $list   = shift;
    my $config = new Vyatta::Config;
    my @rules  = ();

    # remove the old rule if it already exists
    if ( is_access_list($list) ) {
        notify_all_acl_consumers ("-c \"configure terminal\" -c \"no access-list $list\" ");
    }

    $config->setLevel("policy access-list $list rule");
    @rules = $config->listNodes();

    foreach my $rule ( sort numerically @rules ) {
        my ( $ip, $action, $src, $dst, $srcmsk, $dstmsk ) = '';

        # set the action
        $action = $config->returnValue("$rule action");
        if ( !defined $action ) {
            print
"policy access-list $list rule $rule: You must specify an action\n";
            exit 1;
        }

        # TODO: ask someone why config->exists() is returning !0?
        # set the source filter
        if ( defined $config->returnValue("$rule source host") ) {
            $src = $config->returnValue("$rule source host");
            $src = "host " . $src;
        }
        elsif ( defined $config->returnValue("$rule source network") ) {
            $src    = $config->returnValue("$rule source network");
            $srcmsk = $config->returnValue("$rule source inverse-mask");
        }
        else {
            if ( $config->exists("$rule source any") ) { $src = "any"; }
            else {
                print
"policy access-list $list rule $rule source: incorrect source filter\n";
                exit 1;
            }
        }

        # set the destination filter if extended list
        if (   ( ( $list >= 100 ) && ( $list <= 199 ) )
            || ( ( $list >= 2000 ) && ( $list <= 2699 ) ) )
        {
            $ip = 'ip ';

            # TODO: ask someone why config->exists() is returning !0?
            if ( defined $config->returnValue("$rule destination host") ) {
                $dst = $config->returnValue("$rule destination host");
                $dst = "host " . $dst;
            }
            elsif ( defined $config->returnValue("$rule destination network") )
            {
                $dst = $config->returnValue("$rule destination network");
                $dstmsk =
                  $config->returnValue("$rule destination inverse-mask");
            }
            else {
                if ( $config->exists("$rule destination any") ) {
                    $dst = "any";
                }
                else {
                    print
"policy access-list $list rule $rule destination: incorrect destination filter\n";
                    exit 1;
                }
            }
        }
        notify_all_acl_consumers ("-c \"configure terminal\" -c \"access-list $list $action $ip $src $srcmsk $dst $dstmsk\" ");
    }

    exit 0;
}

sub update_access_list6 {
    my $list   = shift;
    my $config = new Vyatta::Config;
    my @rules  = ();

    # remove the old rule if it already exists
    if ( is_access_list6($list) ) {
        notify_all_acl_consumers ("-c \"conf t\" -c \"no ipv6 access-list $list\" "); 
    }

    $config->setLevel("policy access-list6 $list rule");
    @rules = $config->listNodes();

    foreach my $rule ( sort numerically @rules ) {
        my ($action, $src, $exact) = '';

        # set the action
        $action = $config->returnValue("$rule action");
        if ( !defined $action ) {
            print
"policy access-list6 $list rule $rule: You must specify an action\n";
            exit 1;
        }

        if ( defined $config->returnValue("$rule source network") ) {
            $src   = $config->returnValue("$rule source network");
            if ($config->exists("$rule source exact-match")) {
                $exact = 'exact-match';
            }
        }
        else {
            if ( $config->exists("$rule source any") ) { $src = "any"; }
            else {
                print
"policy access-list6 $list rule $rule source: incorrect source filter\n";
                exit 1;
            }
        }
        notify_all_acl_consumers ("-c \"configure terminal\" -c \"ipv6 access-list $list $action $src $exact\" ");
    }

    exit 0;
}

## check_routemap_action
# check if the action has been changed since the last commit.
# we need to do this because quagga will wipe the entire config if
# the action is changed.
# $1 = policy route-map <name> rule <num> action
sub check_routemap_action {
    my $routemap = shift;
    my $config   = new Vyatta::Config;

    my $action    = $config->setLevel("$routemap");
    my $origvalue = $config->returnOrigValue();
    if ($origvalue) {
        my $value = $config->returnValue();
        if ( "$value" ne "$origvalue" ) {
            exit 1;
        }
    }

    exit 0;
}

## check_delete_routemap_action
# don't allow deleteing the route-map action if other sibling nodes exist.
# action is required for all other route-map definitions
# $1 = policy route-map <name> rule <num>
sub check_delete_routemap_action {
    my $routemap = shift;
    my $config   = new Vyatta::Config;

    my @nodes = $config->listNodes("$routemap");

    exit(@nodes) ? 1 : 0;
}

## list available policies
sub list_policy {
   my $policy = shift;
   my $config = new Vyatta::Config;

   $config->setLevel("policy $policy");
   my @nodes = $config->listNodes();
   foreach my $node (@nodes) { print "$node "; }
   return;
}
