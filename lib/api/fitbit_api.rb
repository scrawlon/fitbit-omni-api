module Fitbit
  class Api < OmniAuth::Strategies::Fitbit
    
    def api_call consumer_key, consumer_secret, params, auth_token="", auth_secret=""
      api_params = get_lowercase(params)
      api_error = return_any_api_errors(api_params, auth_token, auth_secret)
      raise api_error if api_error
      access_token = build_request(consumer_key, consumer_secret, auth_token, auth_secret)
      send_api_request(api_params, access_token)
    end

    def build_url api_version, params
      api_url_resources = get_url_resources(params['api-method'])
      api_format = get_response_format(params['response-format'])
      api_ids = add_api_ids(api_url_resources, params)
      api_query = uri_encode_query(params['query']) 
      request_url = "/#{api_version}/#{api_ids}.#{api_format}#{api_query}"
    end

    def get_fitbit_methods
      @@fitbit_methods
    end

    private 

    def return_any_api_errors params, auth_token, auth_secret
      api_error = nil
      api_method = params['api-method']
      fitbit_api_method = @@fitbit_methods[api_method]

      if !fitbit_api_method
        api_error = "#{params['api-method']} is not a valid Fitbit API method." 
      elsif is_missing_required_parameters? fitbit_api_method, params
        api_error = required_parameters_error(api_method, params.keys)
      elsif is_missing_post_parameters? fitbit_api_method, params
        api_error = post_parameters_error(api_method, params['post_parameters'].keys)
      elsif is_breaking_exclusive_post_parameter_rule? fitbit_api_method, params
        api_error = exclusive_post_parameters_error(api_method, params['post_parameters'].keys)
      elsif fitbit_api_method['auth_required'] && (auth_token == "" || auth_secret == "")
        api_error = "#{api_method} requires user auth_token and auth_secret."
      end
    end

    def get_lowercase params
      api_strings = Hash[params.map { |k,v| [k.downcase, v.downcase] if v.is_a? String }]
      api_parameters_and_headers = Hash[params.map { |k,v| [k.downcase, v] if !v.is_a? String }]
      api_strings.merge(api_parameters_and_headers)
    end
    
    def is_fitbit_api_method? api_method
      @@fitbit_methods.has_key? api_method
    end

    def is_missing_required_parameters? api_method, params
      required_parameters = api_method['required_parameters'] 
      (api_method.has_key? 'required_parameters') && (params.keys & required_parameters != required_parameters)
    end

    def is_missing_post_parameters? api_method, params
      required_post_parameters = api_method['post_parameters'].select { |x| !x.is_a? Array } if api_method['post_parameters']
      supplied_post_parameters = params['post_parameters']
      (required_post_parameters) &&
        (!params['post_parameters'] || required_post_parameters - supplied_post_parameters.keys != [])
    end

    def is_breaking_exclusive_post_parameter_rule? api_method, params
      exclusive_post_parameters = get_exclusive_post_parameters api_method
      supplied_post_parameters = params['post_parameters']
      count = 0
      if exclusive_post_parameters && supplied_post_parameters
        supplied_post_parameters.keys.each do |parameter|
          count +=1 if exclusive_post_parameters.include? parameter
        end
      end

      count > 1
    end

    def get_exclusive_post_parameters fitbit_api_method
      post_parameters = fitbit_api_method['post_parameters']
      exclusive_post_parameters = post_parameters.select { |x| x.is_a? Array } if post_parameters 
      exclusive_post_parameters.flatten if exclusive_post_parameters
    end

    def required_parameters_error api_method, supplied
      required = @@fitbit_methods[api_method]['required_parameters'] 
      "#{api_method} requires #{required}. You're missing #{required-supplied}."
    end

    def post_parameters_error api_method, supplied
      required = @@fitbit_methods[api_method]['post_parameters']
      "#{api_method} requires POST Parameters #{required}. You're missing #{required-supplied}."
    end

    def exclusive_post_parameters_error api_method, supplied
      exclusive_post_parameters = get_exclusive_post_parameters @@fitbit_methods[api_method]
      all_supplied = supplied.map { |data| "'#{data}'" }.join(' AND ')
      "#{api_method} allows only one of these POST Parameters #{exclusive_post_parameters}. You used #{all_supplied}."
    end

    def build_request consumer_key, consumer_secret, auth_token, auth_secret
      fitbit = Fitbit::Api.new :fitbit, consumer_key, consumer_secret
      access_token = OAuth::AccessToken.new fitbit.consumer, auth_token, auth_secret
    end

    def send_api_request api_params, access_token
      request_url = build_url(@@api_version, api_params)
      request_http_method = get_http_method(api_params['api-method'])
      request_headers = api_params['request_headers']
      access_token.request( request_http_method, "http://api.fitbit.com#{request_url}", "",  request_headers )
    end
    
    def get_http_method method
      api_http_method = @@fitbit_methods["#{method}"]['http_method']
    end

    def get_url_resources method
      api_method = @@fitbit_methods["#{method.downcase}"]['resources']
      api_method_url = api_method.join("/")
    end

    def get_response_format api_format
      !api_format.nil? && api_format.downcase == 'json' ? 'json' : 'xml'
    end

    def add_api_ids api_url_resources, params
      api_method = params['api-method']
      fitbit_api_method = @@fitbit_methods["#{api_method.downcase}"]
      ids = fitbit_api_method['required_parameters']  
      no_query = ids.reject { |x| x == 'query' } if ids
      no_query.each { |x| api_url_resources << "/#{params[x]}" if params.has_key? x } if ids
      api_url_resources 
    end

    def uri_encode_query query
      if query.nil?
        ""
      else
        api_query = OAuth::Helper.normalize({ 'query' => query }) 
        "?#{api_query}"
      end
    end

    @@api_version = 1

    @@fitbit_methods = {
      'api-search-foods' => {
        'auth_required'       => false,
        'http_method'         => 'get',
        'required_parameters' => ['query'],
        'resources'           => ['foods', 'search'],
      },
      'api-accept-invite' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'post_parameters'     => ['accept'],
        'required_parameters' => ['from-user-id'],
        'resources'           => ['user', '-', 'friends', 'invitations'],
      },
      'api-add-favorite-activity' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'required_parameters' => ['activity-id'],
        'resources'           => ['user', '-', 'activities', 'favorite'],
      },
      'api-add-favorite-food' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'required_parameters' => ['food-id'],
        'resources'           => ['user', '-', 'foods', 'log', 'favorite'],
      },
      'api-browse-activites' => {
        'auth_required'       => false,
        'http_method'         => 'get',
        'request_headers'     => ['accept-locale'],
        'resources'           => ['activities'],
      },
      'api-config-friends-leaderboard' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'post_parameters'     => ['hideMeFromLeaderboard'],
        'request_headers'     => ['accept-language'],
        'resources'           => ['user', '-', 'friends', 'leaderboard'],
      },
      'api-create-food' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'post_parameters'     => ['defaultFoodMeasurementUnitId', 'defaultServingSize', 'calories'],
        'request_headers'     => ['accept-locale'],
        'resources'           => ['foods'],
      },
      'api-create-invite' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'post_parameters'     =>  [['invitedUserEmail', 'invitedUserId']],
        'resources'           => ['user', '-', 'friends', 'invitations'],
      },
      'api-delete-activity-log' => {
        'auth_required'       => true,
        'http_method'         => 'delete',
        'required_parameters' => ['activity-log-id'],
        'resources'           => ['user', '-', 'activities'],
      },
      'api-delete-blood-pressure-log' => {
        'auth_required'       => true,
        'http_method'         => 'delete',
        'required_parameters' => ['bp-log-id'],
        'resources'           => ['user', '-', 'bp'],
      },
      'api-delete-body-fat-log' => {
        'auth_required'       => true,
        'http_method'         => 'delete',
        'required_parameters' => ['body-fat-log-id'],
        'resources'           => ['user', '-', 'body', 'log', 'fat'],
      },
      'api-delete-body-weight-log' => {
        'auth_required'       => true,
        'http_method'         => 'delete',
        'required_parameters' => ['body-weight-log-id'],
        'resources'           => ['user', '-', 'body', 'log', 'weight'],
      },
      'api-delete-favorite-activity' => {
        'auth_required'       => true,
        'http_method'         => 'delete',
        'required_parameters' => ['activity-id'],
        'resources'           => ['user', '-', 'activities', 'favorite'],
      },
      'api-add-favorite-food' => {
        'auth_required'       => true,
        'http_method'         => 'post',
        'required_parameters' => ['food-id'],
        'resources'           => ['user', '-', 'foods', 'log', 'favorite'],
      },
    }

  end

end
