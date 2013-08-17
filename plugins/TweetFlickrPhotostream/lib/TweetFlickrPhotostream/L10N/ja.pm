package TweetFlickrPhotostream::L10N::ja;
use strict;
use base qw( TweetFlickrPhotostream::L10N MT::L10N MT::Plugin::L10N );
use vars qw( %Lexicon );

our %Lexicon = (
    'Available TweetFlickrPhotostream.' => 'タスク実行によって自動的に Flickr の photostream をツイートします。',
    'TweetFlickrPhotostream Task' => 'TweetFlickrPhotostream のタスク',
    'Failed to get response from [_1], ([_2])' => '[_1]から応答を得られません。([_2])',
    'Authorize error' => '認証エラー',
    'Authorize this plugin and enter the PIN#.' => 'アプリケーションの認証を行い、取得されるPIN番号を入力してください。',
    'Get authentication' => '認証を行う',
    'Done' => '実行',
    'Authentication' => '認証',
    'You need authentication about Twitter.' => 'Twitter への認証を行う',
    'Authentication finished.' => '認証が完了しました。ダイアログを閉じると画面の再読み込みが行われます。',
    'Authentication failed.' => '認証に失敗しました。',
    'Already authenticated.' => 'すでに認証されています。',
    'Get authentication again.' => '再度認証を行う',
    'Settings for Twitter' => 'Twitter に関する設定',
    'Settings for Flickr' => 'Flickr に関する設定',
    'Flickr ID' => 'Flickr の ID',
    'Tweet format' => 'ツイートのフォーマット',
    'Update twitter success: [_1]' => 'ツイートしました: [_1]',
    'Tweet limit' => 'ツイートの最大数',
    'Tweet individual photo' => '写真をツイートする',
    'Tweet photo' => 'この写真をツイートする',
    'Bookmarklet' => 'ブックマークレット',
    'This bookmarklet is effective only at Flickr individual photo page.' => 'このブックマークレットは、Flickr の個別写真画面でのみ動作します。',
    'Tweet failed' => 'ツイートに失敗しました',
    'Are you sure you want to tweet photo?' => 'この写真をツイートしてよろしいですか？',
);

1;
