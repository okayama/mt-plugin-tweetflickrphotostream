package TweetFlickrPhotostream::Callbacks;
use strict;

sub _cb_ts_tweetflickrphotostream_config_blog {
	my ( $cb, $app, $tmpl ) = @_;
	my $app_uri = $app->base . $app->uri;
	$$tmpl =~ s/\*app_uri\*/$app_uri/;
}

sub _cb_ts_dashboard {
	my ( $cb, $app, $tmpl ) = @_;
	my $plugin = MT->component( 'TweetFlickrPhotostream' );
    if ( $app->param( 'tweeted-' . lc( $plugin->id ) ) ) {
	    my $message;
	    my $status;
        if ( my $log_id = $app->param( 'log_id' ) ) {
            my $log = MT->model( 'log' )->load( { id => $log_id } );
            if ( $log ) {
                $message = $log->message;
                $status = 'success';
            }
        } else {
            $message = $plugin->translate( 'Tweet failed' );
            $status = 'error';
        }
        my $search = quotemeta( '<mt:include name="include/header.tmpl">' );
        my $insert = $plugin->translate_templatized( <<"MTML" );
<mt:setvarblock name="system_msg" append="1">
<mtapp:statusmsg
    id="tweeted"
    class="$status">
    $message
</mtapp:statusmsg>
</mt:setvarblock>
MTML
        $$tmpl =~ s!($search)!$insert$1!;
    }
}

1;
