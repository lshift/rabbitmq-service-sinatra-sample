require 'sinatra'
require 'erb'
require 'cgi'

require 'bunny'

enable :sessions

# Opens a client connection to the RabbitMQ service, if one isn't
# already open.  This is a class method because a new instance of
# the controller class will be created upon each request.  But AMQP
# connections can be long-lived, so we would like to re-use the
# connection across many requests.
def client
  unless $client
    c = Bunny.new(ENV['RABBITMQ_BIGWIG_URL'])
    c.start
    $client = c

    # We only want to accept one un-acked message
    $client.qos :prefetch_count => 1
  end
  $client
end

# Return the "nameless exchange", pre-defined by AMQP as a means to
# send messages to specific queues.  Again, we use a class method to
# share this across requests.
def nameless_exchange
  $nameless_exchange ||= client.exchange('')
end

# Return a queue named "messages".  This will create the queue on
# the server, if it did not already exist.  Again, we use a class
# method to share this across requests.
def messages_queue
  $messages_queue ||= client.queue("messages")
end

def take_session key
  res = session[key]
  session[key] = nil
  res
end

get '/' do
  @published = take_session(:published)
  @got = take_session(:got)
  erb :index
end

post '/publish' do
  # Send the message from the form's input box to the "messages"
  # queue, via the nameless exchange.  The name of the queue to
  # publish to is specified in the routing key.
  nameless_exchange.publish params[:message], :content_type => "text/plain",
                            :key => "messages"
  # Notify the user that we published.
  session[:published] = true
  redirect to('/')
end

post '/get' do
  session[:got] = :queue_empty

  # Wait for a message from the queue
  messages_queue.subscribe(:ack => true, :timeout => 10,
                           :message_max => 1) do |msg|
    # Show the user what we got
    session[:got] = msg[:payload]
  end

  redirect to('/')
end
