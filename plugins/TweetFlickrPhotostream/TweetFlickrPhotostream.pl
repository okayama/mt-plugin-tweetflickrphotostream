package MT::Plugin::TweetFlickrPhotostream;
use strict;
use MT;
use MT::Plugin;
use base qw( MT::Plugin );

use Encode;
use Encode::Base58;
use HTTP::Request::Common;
use LWP::UserAgent;
use Digest::SHA1;
use Net::OAuth;
use XML::Simple;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A; 

use MT::AtomServer;
use MT::Util qw( offset_time_list );

our $PLUGIN_NAME = 'TweetFlickrPhotostream';
our $PLUGIN_VERSION = '1.0';

my $plugin = new MT::Plugin::TweetFlickrPhotostream( {
    id => $PLUGIN_NAME,
    key => lc $PLUGIN_NAME,
    name => $PLUGIN_NAME,
    version => $PLUGIN_VERSION,
    description => '<MT_TRANS phrase=\'Available TweetFlickrPhotostream.\'>',
    author_name => 'okayama',
    author_link => 'http://weeeblog.net/',
    blog_config_template => 'tweetflickrphotostream_config.tmpl',
    settings => new MT::PluginSettings( [
        [ 'consumer_key' ],
        [ 'consumer_secret' ],
        [ 'callback_url' ],
        [ 'access_token' ],
        [ 'access_secret' ],
        [ 'flickr_id' ],
        [ 'last_modified' ],
        [ 'last_tweeted' ],
        [ 'tweet_format', { Default => 'I uploaded new photo to Flickr: *shoter_url* #flickr #TweetFlickrPhotostream' } ],
    ] ),
    l10n_class => 'MT::TweetFlickrPhotostream::L10N',
} );
MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        applications => {
            cms => {
                methods => {
                    tweetfps_oauth_callback => \&_mode_tweetfps_oauth_callback,
                    tweetfps_oauth_request => \&_mode_tweetfps_oauth_request,
                    tweetfps_oauth_test => \&_mode_tweetfps_oauth_test,
                },
            },
        },
        callbacks => {
            'MT::App::CMS::template_source.tweetflickrphotostream_config' => \&_cb_tp_tweetflickrphotostream_config,
        },
        tasks => {
            tweetflickrphotostream => {
                label => 'TweetFlickrPhotostream Task',
                frequency => 5,
                code => \&tweet_flickr_photostream,
            },
        },
        tags => {
            function => {
                'FlickrShorterURL' => \&_hdlr_flickr_shorter_url,
            },
        },
   } );
}

sub tweet_flickr_photostream_by_id {
    my ( $photo_id, $blog_id ) = @_;
    return unless $photo_id;
    return unless $blog_id;
    if ( ( $photo_id =~ /^[0-9]{1,}$/ ) && ( $blog_id =~ /^[0-9]{1,}$/ ) ) {
        my $scope = 'blog:' . $blog_id;
        if ( my $flickr_id = $plugin->get_config_value( 'flickr_id', $scope ) ) {
            if ( my $shorter_url = get_shorter_url( $photo_id ) ) {
                my $tweet_format = $plugin->get_config_value( 'tweet_format', $scope );
                my $tweet = $tweet_format;
                my $search = quotemeta( '*shoter_url*' );
                $tweet =~ s/$search/$shorter_url/g;
                if ( my $res = _update_twitter( $blog_id, $tweet ) ) {
                    my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
                    _save_success_log( $log_message, $blog_id );
                }
            }
        }
    }
}

sub _hdlr_flickr_shorter_url {
    my ( $ctx, $args, $cond ) = @_;
    if ( my $photo_id = $args->{ photo_id } ) {
        if ( $photo_id =~ /^[0-9]{1,}$/ ) {
            return get_shorter_url( $photo_id ) || '';
        }
    }
    return '';
}

sub tweet_flickr_photostream {
    my @blogs = MT->model( 'blog' )->load( { class => '*' } );
    for my $blog ( @blogs ) {
        my $blog_id = $blog->id;
        my $scope = 'blog:' . $blog_id;
        if ( my $flickr_id = $plugin->get_config_value( 'flickr_id', $scope ) ) {
            if ( my $rss_url = _get_rss_url( $flickr_id ) ) {
                my $tweet_format = $plugin->get_config_value( 'tweet_format', $scope );
                my $last_modified = $plugin->get_config_value( 'last_modified', $scope );
                my $last_tweeted = $plugin->get_config_value( 'last_tweeted', $scope );
                if ( my $tweets = _get_tweet( $blog_id, $rss_url, $tweet_format, $last_modified, $last_tweeted ) ) {
                    my $updated = 0;
                    for my $tweet ( @$tweets ) {
                        if ( my $res = _update_twitter( $blog_id, $tweet ) ) {
                            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
                            _save_success_log( $log_message, $blog_id );
                            $last_tweeted = time;
                            $updated++;
                        }
                    }
                    if ( $updated ) {
                        $plugin->set_config_value( 'last_tweeted', $last_tweeted, $scope );
                    }
                }
            }
        }
    }
}

sub _get_tweet {
    my ( $blog_id, $rss_url, $format, $last_modified, $last_tweeted ) = @_;
    return unless $blog_id;
    return unless $rss_url;
    return unless $format;
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $rss_url ) or return;
    $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
    if ( $last_modified ) {
        $req->header( 'If-Modified-Since' => $last_modified );
    }
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->content;
        my $ref = XMLin( $content, NormaliseSpace => 2 );
        if ( defined $ref->{ xmlns } && $ref->{ xmlns } eq 'http://www.w3.org/2005/Atom' ) {
            my %items = %{ $ref->{ entry } } or return;
            my @tweets;
            for my $key ( keys %items ) {
                my $updated = $items{ $key }->{ updated };
                my $updated_epoch = MT::AtomServer::iso2epoch( undef, $updated );
                if ( $last_tweeted && ( $updated_epoch < $last_tweeted ) ) {
                    next;
                }
                if ( my $photo_id = $key ) {
                    $photo_id =~ s!.*/([0-9]{1,})!$1!;
                    if ( my $shorter_url = get_shorter_url( $photo_id ) ) {
                        my $tweet = $format;
                        my $search = quotemeta( '*shoter_url*' );
                        $tweet =~ s/$search/$shorter_url/g;
                        push( @tweets, $tweet );
                        unless ( $last_modified ) {
                            last;
                        }
                    }
                }
            }
            my $scope = 'blog:' . $blog_id;
            $plugin->set_config_value( 'last_modified', $res->header( 'Last-Modified' ), $scope );
            return \@tweets;
        }
    } else {
#        my $log_message = $plugin->translate( 'Getting RSS failed.' );
#        _save_error_log( $log_message, $blog_id );
    }
    return 0;
}

sub get_shorter_url {
    my ( $photo_id ) = @_;
    return unless $photo_id;
    if ( $photo_id =~ /^[0-9]{1,}$/ ) {
        if ( my $encoded = encode_base58( $photo_id ) ) {
            return 'http://flic.kr/p/'. $encoded;
        }
    }
    return '';
}

sub _get_rss_url {
    my ( $flickr_id ) = @_;
    if ( $flickr_id ) {
        return 'http://api.flickr.com/services/feeds/photos_public.gne?id=' . $flickr_id . '&lang=en-us&format=atom';
    }
}

sub _update_twitter {
    my ( $blog_id, $message, $options ) = @_;
    my $scope = 'blog:' . $blog_id;
    my $consumer_key = $plugin->get_config_value( 'consumer_key', $scope );
    my $consumer_secret = $plugin->get_config_value( 'consumer_secret', $scope );
    my $access_token = $plugin->get_config_value( 'access_token', $scope );
    my $access_secret = $plugin->get_config_value( 'access_secret', $scope );

    my $tweet = MT::I18N::decode_utf8( $message );
    
    my $api_request_url  = 'https://twitter.com/statuses/update.xml';
    my $request_method = 'POST'; 
    
    my $request  = Net::OAuth->request( "protected resource" )->new(
        consumer_key    => $consumer_key,
        consumer_secret => $consumer_secret,
        request_url => $api_request_url,
        request_method => $request_method,
        signature_method => 'HMAC-SHA1',
        timestamp => time,
        nonce => Digest::SHA1::sha1_base64( time . $$ . rand ),
        token => $access_token,
        token_secret => $access_secret,
        extra_params => { status => $tweet },
    );
    $request->sign;

    my $ua = LWP::UserAgent->new;
    my $http_header = HTTP::Headers->new( 'User-Agent' => $PLUGIN_NAME );
    my $http_request = HTTP::Request->new( $request_method, $api_request_url, $http_header, $request->to_post_body );
    my $res = $ua->request( $http_request );
    unless ( $res->is_success ) {
        my $log = $plugin->translate( 'Error update twitter: [_1]', $res->status_line );
        _save_error_log( $log, $blog_id );
        return 0;
    }
    return $tweet;
}

sub _mode_tweetfps_oauth_test {
    my $app = shift;
    my %param;
    if ( my $blog_id = $app->param( 'blog_id' ) ) {
        my $scope = 'blog:' . $blog_id;
        my $consumer_key = $plugin->get_config_value( 'consumer_key', $scope );
        my $consumer_secret = $plugin->get_config_value( 'consumer_secret', $scope );
        my $access_token = $plugin->get_config_value( 'access_token', $scope );
        my $access_secret = $plugin->get_config_value( 'access_secret', $scope );
        my $blog = MT->model( 'blog' )->load( { id => $blog_id } );
        my @tl = offset_time_list( time, $blog );
        my $ts = sprintf "%04d%02d%02d%02d%02d%02d", $tl[ 5 ] + 1900, $tl[ 4 ] + 1, @tl[ 3, 2, 1, 0 ];
        use MT::Template::Context;
        my $ctx = MT::Template::Context->new;
        my $datetime = $ctx->build_date( { ts => $ts,
                                           'format' => "%Y-%m-%dT%H:%M:%S",
                                         }
                                       );
        my $message = $plugin->translate( 'This post is test for TweetFlickrPhotostream' ) . ': ' . $datetime;
        if ( _update_twitter( $blog_id, $message ) ) {
            $param{ 'page_title' } = $plugin->translate( 'Test post success!' );
            $param{ 'msg' } = $plugin->translate( 'Please check your twitter.' );
            $param{ 'is_success' } = 1;
        }
    }
    unless ( $param{ 'is_success' } ) {
        $param{ 'page_title' } = $plugin->translate( 'Test post failed!' );
        $param{ 'msg' } = $plugin->translate( 'Test post failed. Please check your settings.' );
    }
    $app->{ plugin_template_path } = File::Spec->catdir( $plugin->path,'tmpl' );
    my $tmpl = 'tweetflickrphotostream_authorized.tmpl';
    return $app->build_page( $tmpl, \%param );
}

sub _mode_tweetfps_oauth_request {
    my $app = shift;
    if ( my $blog_id = $app->param( 'blog_id' ) ) {
        my $scope = 'blog:' . $blog_id;
        my $consumer_key = $plugin->get_config_value( 'consumer_key', $scope );
        my $consumer_secret = $plugin->get_config_value( 'consumer_secret', $scope );
        my $callback_url = $plugin->get_config_value( 'callback_url', $scope );
        
        my $request_token_url = 'http://twitter.com/oauth/request_token';
        my $request_method = 'GET';
        my $request = Net::OAuth->request( "request token" )->new(
            consumer_key => $consumer_key,
            consumer_secret => $consumer_secret,
            request_url => $request_token_url,
            request_method => $request_method,
            signature_method => 'HMAC-SHA1',
            timestamp => time,
            nonce => Digest::SHA1::sha1_base64( time . $$ . rand ),
            callback => $callback_url,
        );    
        $request->sign;
    
        my $ua = LWP::UserAgent->new;
        my $http_header = HTTP::Headers->new( 'Authorization' => $request->to_authorization_header );
        my $http_request = HTTP::Request->new( $request_method, $request_token_url, $http_header );
        my $res = $ua->request( $http_request );
        if ( $res->is_success ) {
            my $response = Net::OAuth->response( 'request token' )->from_post_body( $res->content );
            my $request_token = $response->token;
            my $request_token_secret = $response->token_secret;
            my $authorize_url = 'http://twitter.com/oauth/authorize?oauth_token=' . $request_token;
            my $cookie = $app->bake_cookie( -name=>'tweetflickrphotostream',
                                            -value => { blog_id => $blog_id,
                                                        token => $request_token,
                                                        token_secret => $request_token_secret,
                                                      },
                                            -path => '/',
                                          );
            return $app->redirect( $authorize_url, UseMeta => 1, -cookie => $cookie );
        }
    }
    my %param;
    $param{ 'page_title' } = $plugin->translate( 'OAuth failed!' );
    $param{ 'msg' } = $plugin->translate( 'OAuth failed. Please check your settings' );
    $app->{ plugin_template_path } = File::Spec->catdir( $plugin->path,'tmpl' );
    my $tmpl = 'tweetflickrphotostream_authorized.tmpl';
    return $app->build_page( $tmpl, \%param );
}

sub _mode_tweetfps_oauth_callback {
    my $app = shift;
    my $cookies = $app->cookies();
    my %param;
    if ( my %cookies = $cookies->{ 'tweetflickrphotostream' }->value ) {
        my $blog_id = $cookies{ 'blog_id' };
        my $request_token = $cookies{ 'token' };
        my $request_token_secret = $cookies{ 'token_secret' };
        my $oauth_token = $app->param( 'oauth_token' );
        my $verifier = $app->param( 'oauth_verifier' );
        my $scope = 'blog:' . $blog_id;
        my $consumer_key = $plugin->get_config_value( 'consumer_key', $scope );
        my $consumer_secret = $plugin->get_config_value( 'consumer_secret', $scope );
        my $access_token_url = 'http://twitter.com/oauth/access_token';
        my $request_method = 'POST';
        my $request = Net::OAuth->request( "access token" )->new(
            consumer_key => $consumer_key,
            consumer_secret => $consumer_secret,
            request_url => $access_token_url,
            request_method => $request_method,
            signature_method => 'HMAC-SHA1',
            timestamp => time,
            nonce => Digest::SHA1::sha1_base64( time . $$ . rand ),
            token => $oauth_token,
            verifier => $verifier,
            token_secret => $request_token_secret,
        );
        my $ua = LWP::UserAgent->new;
        my $http_header = HTTP::Headers->new( 'User-Agent' => $PLUGIN_NAME );
        my $http_request = HTTP::Request->new( $request_method, $access_token_url, $http_header, $request->to_post_body );
        my $res = $ua->request( $http_request );
        if ( $res->is_success ) {
            $param{ 'page_title' } = $plugin->translate( 'Get Access Token Success!' );
            my $test_post_uri = $app->base . $app->uri( mode => 'tweetfps_oauth_test', args => { blog_id => $blog_id } );
            $param{ 'msg' } = $plugin->translate( 'Get Access Token Success! <a href="[_1]">click to test post</a>.', $test_post_uri );
            $param{ 'is_success' } = 1;
            $param{ 'show_table' } = 1;
            my $response = Net::OAuth->response( 'access token' )->from_post_body( $res->content );
            if ( my $access_token = $response->token ) {
                $plugin->set_config_value( 'access_token', $access_token, $scope );
                $param{ 'access_token' } = $access_token;
            }
            if ( my $access_secret = $response->token_secret ) {
                $plugin->set_config_value( 'access_secret', $access_secret, $scope );
                $param{ 'access_secret' } = $access_secret;
            }
        }
    }
    unless ( $param{ 'is_success' } ) {
        $param{ 'page_title' } = $plugin->translate( 'Get Access Token failed!' );
        $param{ 'msg' } = $plugin->translate( 'Get Access Token failed!' );
    }
    $app->{ plugin_template_path } = File::Spec->catdir( $plugin->path,'tmpl' );
    my $tmpl = 'tweetflickrphotostream_authorized.tmpl';
    return $app->build_page( $tmpl, \%param );
}

sub _cb_tp_tweetflickrphotostream_config {
    my ( $cb, $app, $tmpl ) = @_;
    my ( $search, $replace );
    $search = quotemeta( '<[*mt_dir_uri*]>' );
    $replace = $app->base . $app->mt_path;
    $$tmpl =~ s/$search/$replace/g;
    $search = quotemeta( '<[*this_blog_id*]>' );
    $replace = $app->param( 'blog_id' );
    $$tmpl =~ s/$search/$replace/g;
}

sub _save_success_log {
    my ( $message, $blog_id ) = @_;
    _save_log( $message, $blog_id, MT::Log::INFO() );
}

sub _save_error_log {
    my ( $message, $blog_id ) = @_;
    _save_log( $message, $blog_id, MT::Log::ERROR() );
}

sub _save_log {
    my ( $message, $blog_id, $log_level ) = @_;
    if ( $message ) {
        my $log = MT::Log->new;
        $log->message( $message );
        $log->class( 'tweetflickrphotostream' );
        $log->blog_id( $blog_id );
        $log->level( $log_level );
        $log->save or die $log->errstr;
    }
}

sub _debug {
    my ( $data ) = @_;
    use Data::Dumper;
    MT->log( Dumper( $data ) );
}

1;
