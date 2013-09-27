# OmniAuth Fitbit Strategy

This gem is an OmniAuth 1.0+ Strategy for the [Fitbit API](https://wiki.fitbit.com/display/API/OAuth+Authentication+in+the+Fitbit+API).

## Usage

Add the strategy to your `Gemfile`:

```ruby
gem 'omniauth-fitbit'
```

Then integrate the strategy into your middleware:

```ruby
use OmniAuth::Builder do
  provider :fitbit, 'consumer_key', 'consumer_secret'
end
```

In Rails, create a new file under config/initializers called omniauth.rb to plug the strategy into your middleware stack.

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :fitbit, 'consumer_key', 'consumer_secret'
end
```

To register your application with Fitbit and obtain a consumer key and secret, go to the [Fitbit application registration](https://dev.fitbit.com/apps/new).

For additional information about OmniAuth, visit [OmniAuth wiki](https://github.com/intridea/omniauth/wiki).

For a short tutorial on how to use OmniAuth in your Rails application, visit [this tutsplus.com tutorial](http://net.tutsplus.com/tutorials/ruby/how-to-use-omniauth-to-authenticate-your-users/).

## Accessing the Fitbit API

An API call can be instantiated with `Fitbit::Api.new({}).api_call()`  
Each call requires:
* Fitbit consumer_key and consumer_secret
* A params Hash containing the Fitbit API method, plus all required parameters 
* Optionally, for authenticated API calls, your user's Fitbit auth token and auth secret

An example of an authenticated API call: 

```ruby
Fitbit::Api.new({}).api_call(
  'consumer_key',
  'consumer_secret',
  params,
  'auth_token',
  'auth_secret'
)
```

OmniAuth Fitbit supports the Fitbit Resource Access API and the Fitbit Subscriptions API.

To access the Resource Access API, consult the API docs and provide the required parameters. For example,
the API-Search-Foods method requires 'api-version', 'query' and 'response-format'. There's also an optional
Request Header parameter, 'Accept-Locale'. A call to API-Search-Foods might look like this:

```ruby
def fibit_foods_search
  params = {
    'api-method'      => 'api-search-foods',
    'query'           => 'buffalo chicken',
    'response-format' => 'json',
    'Accept-Locale'   => 'en_US',
  }
  request = Fitbit::Api.new({}).api_call(
    'consumer_key',
    'consumer_secret',
    params,
    'auth_token',
    'auth_secret'
  )
  @response = request.body
end
```

A few notes: 'api-version' defaults to '1' and can be omitted from OmniAuth Fitbit API calls.
If you omit the 'response-format', the response will be in the default xml format.
Some authenticated API methods can be accessed without auth tokens, if you supply a user's
user-id (see the API docs for details).

To access the Subscription API, two new api methods were created just for this gem:
API-Create-Subscription and API-Delete-Subscription. These api methods only exist in this gem,
not the Fitbit API. If you consult the Subscription API docs for adding and deleting subscriptions,
and supply the required parameters, these two api methods work just as described for the
Resource Access API. NOTE: To subscribe to ALL of a user's changes, make 'collection-path' = 'all'.

## Copyright

Copyright (c) 2012 TK Gospodinov, (c) Scott McGrath 2013. See [LICENSE](https://github.com/tkgospodinov/omniauth-fitbit/blob/master/LICENSE.md) for details.
