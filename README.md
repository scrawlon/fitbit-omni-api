# Fitbit-Omni-Api

This gem uses the [OmniAuth-Fitbit Strategy](https://github.com/tkgospodinov/omniauth-fitbit) for authentication.
See that repo for more info.

## Accessing the Fitbit API
## There are breaking changes in this version.

## Installation

Add the gem to your Gemfile
```ruby
gem 'fitbit-omni-api'
```

The gem class is simply 'Fitbit::Api' and Fitbit Api requests are made with the 'Fitbit::Api.request' method.

Each API request needs:
* your Fitbit consumer_key and consumer_secret (acquired from [dev.fitbit.com](http://dev.fitbit.cpm))
* A params Hash with api-method and required parameters 
* Optionally, Fitbit auth tokens or user-id if required 

An example of an authenticated API call: 

```ruby
Fitbit::Api.request(
  'consumer_key',
  'consumer_secret',
  params = { 'api-method' => 'api-method-here', 'start-time' => '00:00' }
  'auth_token',
  'auth_secret'
)
```

This gem supports the Fitbit Resource Access API and the Fitbit Subscriptions API.

To access the Resource Access API, consult the API docs and provide the required parameters. For example,
the API-Search-Foods method requires 'api-version', 'query' and 'response-format'. There's also an optional
Request Header parameter, 'Accept-Locale'. A call to API-Search-Foods might look like this:

```ruby
def fitbit_foods_search
  params = {
    'api-method'      => 'api-search-foods',
    'query'           => 'buffalo chicken',
    'response-format' => 'json',
    'Accept-Locale'   => 'en_US',
  }
  request = Fitbit::Api.request(
    'consumer_key',
    'consumer_secret',
    params,
    'auth_token',
    'auth_secret'
  )
  @response = request.body
end
```

A few notes: 'api-version' defaults to '1' and can be omitted from Fitbit-Omni-Api calls.
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
