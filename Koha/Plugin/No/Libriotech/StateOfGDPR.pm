package Koha::Plugin::No::Libriotech::StateOfGDPR;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;

## Here we set our plugin version
our $VERSION = "0.0.1";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'State of GDPR',
    author          => 'Magnus Enger',
    date_authored   => '2019-08-28',
    date_updated    => '2019-08-28',
    minimum_version => undef,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Tries to give some insights into the state of GDPR-compliance in your Koha instance.',
};

my $dbh = C4::Context->dbh;

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'report' subroutine means the plugin is capable
## of running a report. This example report can output a list of patrons
## either as HTML or as a CSV file. Technically, you could put all your code
## in the report method, but that would be a really poor way to write code
## for all but the simplest reports
sub report {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    $self->main();

}

sub main {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'main.tt' });

    my $anonymouspatron = C4::Context->preference( 'AnonymousPatron' );

    # Deleted borrowers
    $template->param(
        deletedborrowers => _get_value( "SELECT COUNT(*) FROM deletedborrowers" ),
        deletedborrowers_newest => _get_value( "SELECT MAX( updated_on ) FROM deletedborrowers" ),
        deletedborrowers_oldest => _get_value( "SELECT MIN( updated_on ) FROM deletedborrowers" ),
    );

    # Gender
    $template->param(
        gender => _get_value( "SELECT COUNT(*) FROM borrowers WHERE ( sex IS NOT NULL AND sex != '' )" ),
        gender_del => _get_value( "SELECT COUNT(*) FROM deletedborrowers WHERE ( sex IS NOT NULL AND sex != '' )" ),
    );

    # Old loans
    $template->param(
        anonymouspatron => $anonymouspatron,
        old_issues => _get_value( "SELECT COUNT(*) FROM old_issues" ),
        old_issues_anonymized => _get_value( "SELECT COUNT(*) FROM old_issues WHERE borrowernumber = $anonymouspatron" ),
        old_issues_nonanon_oldest => _get_value( "SELECT MIN( timestamp ) FROM old_issues where borrowernumber != $anonymouspatron" ),
        not_anon => _get_multi( "SELECT c.description, b.categorycode, c.default_privacy, COUNT(*) AS count 
                                 FROM old_issues oi 
                                   LEFT JOIN borrowers b ON oi.borrowernumber = b.borrowernumber 
                                   LEFT JOIN categories c ON b.categorycode = c.categorycode 
                                 WHERE oi.borrowernumber != $anonymouspatron 
                                 GROUP BY b.categorycode" ),
    );

    # Old reserves
    $template->param(
        old_reserves => _get_value( "SELECT COUNT(*) FROM old_reserves" ),
        old_reserves_anonymized => _get_value( "SELECT COUNT(*) FROM old_reserves WHERE borrowernumber = $anonymouspatron" ),
        old_reserves_nonanon_oldest => _get_value( "SELECT MIN( timestamp ) FROM old_reserves WHERE borrowernumber != $anonymouspatron" ),
        old_reserves_age => _get_multi( "SELECT YEAR( timestamp ) AS year, COUNT(*) AS count FROM old_reserves WHERE borrowernumber != $anonymouspatron GROUP BY year" ),
    );

    # Privacy
    $template->param(
        opacprivacy => C4::Context->preference( 'OPACPrivacy' ),
        opacuserlogin => C4::Context->preference( 'opacuserlogin' ),
        privacy => _get_multi( "SELECT b.categorycode, c.description, c.default_privacy, b.privacy, count(*) AS count
                                FROM borrowers b 
                                  LEFT JOIN categories c ON b.categorycode = c.categorycode
                                GROUP BY categorycode, privacy" ),
    );

    # Last borrower
    $template->param(
        storelastborrower => C4::Context->preference( 'StoreLastBorrower' ),
        items_last_borrower => _get_value( "SELECT COUNT(*) FROM items_last_borrower" ),
        items_last_borrower_oldest => _get_value( "SELECT MIN(created_on) FROM items_last_borrower" ),
    );

    # Statistics
    # All:            SELECT type, COUNT(*) AS count FROM statistics GROUP BY type;
    $template->param(
        stats_anon    => _get_multi( "SELECT type, COUNT(*) AS count FROM statistics WHERE ( borrowernumber = $anonymouspatron OR borrowernumber IS NULL ) GROUP BY type" ),
        stats_nonanon => _get_multi( "SELECT type, COUNT(*) AS count FROM statistics WHERE ( borrowernumber != $anonymouspatron AND borrowernumber IS NOT NULL ) GROUP BY type" ),
        stats_age => _get_multi( "SELECT YEAR( datetime ) AS year, COUNT(*) AS count FROM statistics WHERE borrowernumber != $anonymouspatron GROUP BY year" ),
    );

    # Messages
    $template->param(
        messages_nonanon => _get_value( "SELECT COUNT(*) FROM message_queue WHERE ( borrowernumber != $anonymouspatron OR borrowernumber IS NULL ) AND status != 'pending'" ),
        messages_nonanon_oldest => _get_value( "SELECT MIN(time_queued) FROM message_queue WHERE ( borrowernumber != $anonymouspatron OR borrowernumber IS NULL ) AND status != 'pending'" ),
        messages_age => _get_multi( "SELECT YEAR( time_queued ) AS year, COUNT(*) AS count FROM message_queue WHERE borrowernumber != $anonymouspatron AND status != 'pending' GROUP BY year" ),
    );

    $self->output_html( $template->output() );
}

sub _get_multi {

    my ( $sql ) = @_;

    my $sth = $dbh->prepare( $sql );
    $sth->execute();

    my @results;
    while ( my $row = $sth->fetchrow_hashref() ) {
        push( @results, $row );
    }

    return \@results;

}

sub _get_value {

    my ( $sql ) = @_;

    my $query = $sql;
    my $sth = $dbh->prepare($query);
    $sth->execute();
    my ( $value ) = $sth->fetchrow_array();

    return $value;

}

1;
