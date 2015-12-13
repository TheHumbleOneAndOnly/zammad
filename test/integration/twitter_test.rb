# encoding: utf-8
require 'integration_test_helper'

class TwitterTest < ActiveSupport::TestCase

  # set system mode to done / to activate
  Setting.set('system_init_done', true)

  # needed to check correct behavior
  Group.create_if_not_exists(
    id: 2,
    name: 'Twitter',
    note: 'All Tweets.',
    updated_by_id: 1,
    created_by_id: 1
  )

  # app config
  if !ENV['TWITTER_APP_CONSUMER_KEY']
    fail "ERROR: Need TWITTER_APP_CONSUMER_KEY - hint TWITTER_APP_CONSUMER_KEY='1234'"
  end
  if !ENV['TWITTER_APP_CONSUMER_SECRET']
    fail "ERROR: Need TWITTER_APP_CONSUMER_SECRET - hint TWITTER_APP_CONSUMER_SECRET='1234'"
  end
  consumer_key    = ENV['TWITTER_APP_CONSUMER_KEY']
  consumer_secret = ENV['TWITTER_APP_CONSUMER_SECRET']

  # armin_theo (is system and is following marion_bauer)
  if !ENV['TWITTER_SYSTEM_TOKEN']
    fail "ERROR: Need TWITTER_SYSTEM_TOKEN - hint TWITTER_SYSTEM_TOKEN='1234'"
  end
  if !ENV['TWITTER_SYSTEM_TOKEN_SECRET']
    fail "ERROR: Need TWITTER_SYSTEM_TOKEN_SECRET - hint TWITTER_SYSTEM_TOKEN_SECRET='1234'"
  end
  armin_theo_token        = ENV['TWITTER_SYSTEM_TOKEN']
  armin_theo_token_secret = ENV['TWITTER_SYSTEM_TOKEN_SECRET']

  # me_bauer (is following armin_theo)
  if !ENV['TWITTER_CUSTOMER_TOKEN']
    fail "ERROR: Need CUSTOMER_TOKEN - hint TWITTER_CUSTOMER_TOKEN='1234'"
  end
  if !ENV['TWITTER_CUSTOMER_TOKEN_SECREET']
    fail "ERROR: Need CUSTOMER_TOKEN_SECREET - hint TWITTER_CUSTOMER_TOKEN_SECREET='1234'"
  end
  me_bauer_token        = ENV['TWITTER_CUSTOMER_TOKEN']
  me_bauer_token_secret = ENV['TWITTER_CUSTOMER_TOKEN_SECREET']

  # add channel
  current = Channel.where(area: 'Twitter::Account')
  current.each(&:destroy)
  Channel.create(
    area: 'Twitter::Account',
    options: {
      adapter: 'twitter',
      auth: {
        consumer_key:       consumer_key,
        consumer_secret:    consumer_secret,
        oauth_token:        armin_theo_token,
        oauth_token_secret: armin_theo_token_secret,
      },
      sync: {
        search: [
          {
            term: '#citheo42',
            group_id: 2,
          },
          {
            term: '#citheo24',
            group_id: 1,
          },
        ],
        mentions: {
          group_id: 2,
        },
        direct_messages: {
          group_id: 2,
        }
      }
    },
    active: true,
    created_by_id: 1,
    updated_by_id: 1,
  )

  test 'a new outbound and reply' do

    hash   = '#citheo42' + rand(9999).to_s
    user   = User.find(2)
    text   = "Today the weather is really nice... #{hash}"
    ticket = Ticket.create(
      title:         text[0, 40],
      customer_id:   user.id,
      group_id:      2,
      state:         Ticket::State.find_by(name: 'new'),
      priority:      Ticket::Priority.find_by(name: '2 normal'),
      updated_by_id: 1,
      created_by_id: 1,
    )
    assert(ticket, "outbound ticket created, text: #{text}")

    article = Ticket::Article.create(
      ticket_id:     ticket.id,
      body:          text,
      type:          Ticket::Article::Type.find_by(name: 'twitter status'),
      sender:        Ticket::Article::Sender.find_by(name: 'Agent'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )
    assert(article, "outbound article created, text: #{text}")

    # reply by me_bauer
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = consumer_key
      config.consumer_secret     = consumer_secret
      config.access_token        = me_bauer_token
      config.access_token_secret = me_bauer_token_secret
    end

    tweet_found = false
    client.user_timeline('armin_theo').each { |tweet|

      next if tweet.id.to_s != article.message_id.to_s
      tweet_found = true
      break
    }
    assert(tweet_found, "found outbound '#{text}' tweet '#{article.message_id}'")

    reply_text = '@armin_theo on my side the weather is nice, too! 😍😍😍 #weather' + rand(9999).to_s
    tweet = client.update(
      reply_text,
      {
        in_reply_to_status_id: article.message_id
      }
    )

    # fetch check system account
    sleep 10

    # fetch check system account
    article = nil
    (1..2).each {
      Channel.fetch

      # check if follow up article has been created
      article = Ticket::Article.find_by(message_id: tweet.id)

      break if article

      sleep 10
    }

    assert(article, "article tweet '#{tweet.id}' imported")
    assert_equal('armin_theo', article.from, 'ticket article inbound from')
    assert_equal(nil, article.to, 'ticket article inbound to')
    assert_equal(tweet.id.to_s, article.message_id, 'ticket article inbound message_id')
    assert_equal(2, article.ticket.articles.count, 'ticket article inbound count')
    assert_equal(reply_text.utf8_to_3bytesutf8, ticket.articles.last.body, 'ticket article inbound body')
  end

  test 'b new inbound and reply' do

    # new tweet by me_bauer
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = consumer_key
      config.consumer_secret     = consumer_secret
      config.access_token        = me_bauer_token
      config.access_token_secret = me_bauer_token_secret
    end

    hash  = '#citheo24 #' + rand(9999).to_s
    text  = "Today... #{hash}"
    tweet = client.update(
      text,
    )
    sleep 10

    # fetch check system account
    article = nil
    (1..2).each {
      Channel.fetch

      # check if ticket and article has been created
      article = Ticket::Article.find_by(message_id: tweet.id)

      break if article

      sleep 10
    }
    assert(article)
    ticket = article.ticket

    # send reply
    reply_text = '@armin_theo on my side #weather' + rand(9999).to_s
    article = Ticket::Article.create(
      ticket_id:     ticket.id,
      body:          reply_text,
      type:          Ticket::Article::Type.find_by(name: 'twitter status'),
      sender:        Ticket::Article::Sender.find_by(name: 'Agent'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )
    assert(article, "outbound article created, text: #{reply_text}")
    assert_equal(nil, article.to, 'ticket article outbound to')
    sleep 5
    tweet_found = false
    client.user_timeline('armin_theo').each { |local_tweet|
      next if local_tweet.id.to_s != article.message_id.to_s
      tweet_found = true
      break
    }
    assert(tweet_found, "found outbound '#{reply_text}' tweet '#{article.message_id}'")
  end

  test 'c new by direct message inbound' do

    # cleanup direct messages of system
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = consumer_key
      config.consumer_secret     = consumer_secret
      config.access_token        = armin_theo_token
      config.access_token_secret = armin_theo_token_secret
    end
    dms = client.direct_messages(count: 40)
    dms.each {|dm|
      client.destroy_direct_message(dm.id)
    }
    client = Twitter::REST::Client.new(
      consumer_key:        consumer_key,
      consumer_secret:     consumer_secret,
      access_token:        me_bauer_token,
      access_token_secret: me_bauer_token_secret
    )
    dms = client.direct_messages(count: 40)
    dms.each {|dm|
      client.destroy_direct_message(dm.id)
    }
    hash  = '#citheo44' + rand(9999).to_s
    text  = 'How about the details? ' + hash
    dm = client.create_direct_message(
      'armin_theo',
      text,
    )
    assert(dm, "dm with ##{hash} created")
    sleep 10

    # fetch check system account
    article = nil
    (1..2).each {
      Channel.fetch

      # check if ticket and article has been created
      article = Ticket::Article.find_by(message_id: dm.id)

      break if article

      sleep 10
    }

    assert(article, "inbound article '#{text}' created")
    ticket = article.ticket
    assert(ticket, 'ticket of inbound article exists')
    assert(ticket.articles, 'ticket.articles exists')
    assert_equal(1, ticket.articles.count, 'ticket article inbound count')
    assert_equal(ticket.state.name, 'new')

    # reply via ticket
    outbound_article = Ticket::Article.create(
      ticket_id:     ticket.id,
      to:            'me_bauer',
      body:          'Will call you later!',
      type:          Ticket::Article::Type.find_by(name: 'twitter direct-message'),
      sender:        Ticket::Article::Sender.find_by(name: 'Agent'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )
    ticket.state = Ticket::State.find_by(name: 'pending reminder')
    ticket.save

    assert(outbound_article, 'outbound article created')
    assert_equal(2, outbound_article.ticket.articles.count, 'ticket article outbound count')

    text  = 'Ok. ' + hash
    dm = client.create_direct_message(
      'armin_theo',
      text,
    )
    assert(dm, "second dm with ##{hash} created")
    sleep 10

    # fetch check system account
    article = nil
    (1..2).each {
      Channel.fetch

      # check if ticket and article has been created
      article = Ticket::Article.find_by(message_id: dm.id)

      break if article

      sleep 10
    }

    assert(article, "inbound article '#{text}' created")
    assert_equal(article.ticket.id, ticket.id, 'still the same ticket')
    ticket = article.ticket
    assert(ticket, 'ticket of inbound article exists')
    assert(ticket.articles, 'ticket.articles exists')
    assert_equal(3, ticket.articles.count, 'ticket article inbound count')
    assert_equal(ticket.state.name, 'open')

    # close dm ticket, next dm should open a new
    ticket.state = Ticket::State.find_by(name: 'closed')
    ticket.save

    text = 'Thanks for your call . I just have one question. ' + hash
    dm   = client.create_direct_message(
      'armin_theo',
      text,
    )
    assert(dm, "third dm with ##{hash} created")

    # fetch check system account
    article = nil
    (1..2).each {
      Channel.fetch

      # check if ticket and article has been created
      article = Ticket::Article.find_by(message_id: dm.id)

      break if article

      sleep 10
    }

    assert(article, "inbound article '#{text}' created")
    ticket = article.ticket
    assert(ticket, 'ticket of inbound article exists')
    assert(ticket.articles, 'ticket.articles exists')
    assert_equal(1, ticket.articles.count, 'ticket article inbound count')
    assert_equal(ticket.state.name, 'new')
  end

end
