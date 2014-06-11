# Fitbit-Omni-Api

This gem uses the [OmniAuth-Fitbit Strategy](https://github.com/tkgospodinov/omniauth-fitbit) for authentication.
See that repo for more info.

## Accessing the Fitbit API
### There are breaking changes in this version.

### Installation

Add the gem to your Gemfile
```ruby
gem 'fitbit-omni-api'
```

The gem class is simply 'Fitbit::Api' and Fitbit Api requests are made with the 'Fitbit::Api.request' method.

Each API request needs:
* Your Fitbit consumer_key and consumer_secret (acquired from [dev.fitbit.com](http://dev.fitbit.cpm))
* A params Hash with api-method and required parameters 
* Optionally, Fitbit auth tokens or user-id if required 

This is the structure of an authenticated API call: 

```ruby
Fitbit::Api.request(
  'consumer_key',
  'consumer_secret',
  params = { 'api-method' => 'api-method-here', 'start-time' => '00:00' }
  'auth_token',
  'auth_secret'
)
```

This gem supports the Fitbit Resource Access API, Fitbit Subscriptions API and Fitbit Partner API.

To access the Resource Access API, consult the API docs and provide the required parameters. For example,
the API-Search-Foods method requires _'api-version'_, _'query'_ and _'response-format'_, plus there's an optional
_'Accept-Locale'_  Request Header parameter.

A call to API-Search-Foods might look like this:

```ruby
def fitbit_foods_search
  request = Fitbit::Api.request(
    'consumer_key',
    'consumer_secret',
    params={'api-method'=>'api-search-foods','query'=>'buffalo chicken','Accept-Locale'=>'en_US'}
    'auth_token',
    'auth_secret'
  )
  @response = request.body
end
```

### Fitbit Subscriptions API
Use API-Create-Subscription and API-Delete-Subscription API methods to to access the Subscription API.
Consult the Subscription API docs to discover the required parameters.
To subscribe to ALL of a user's changes, make 'collection-path' = 'all'.

### Fitbit Partner API
These features are only accessible with approved Fitbit developer accounts. 

### Defaults:
* 'api-version' defaults to '1'
* 'response-format' defaults to 'xml'

### Copyright

Copyright (c) 2012 TK Gospodinov, (c) Scott McGrath 2013. See [LICENSE](https://github.com/scrawlon/fitbit-omni-api/blob/master/LICENSE.md) for details.
