require 'omniauth-fitbit'

module Fitbit
  class Api < OmniAuth::Strategies::Fitbit
    
    def api_call consumer_key, consumer_secret, params, auth_token="", auth_secret=""
      begin 
        fitbit_api_method = get_api_method(params['api-method'])
        verify_api_call(params, fitbit_api_method, auth_token, auth_secret)
      rescue => e
        raise e
      end
      access_token = build_request(consumer_key, consumer_secret, auth_token, auth_secret)
      send_api_request(params, fitbit_api_method, access_token)
    end

    def get_fitbit_methods
      @@fitbit_methods
    end

    private 

    def get_api_method api_method
      return nil unless api_method and api_method.is_a? String
      api_method.downcase!
      @@fitbit_methods[api_method]
    end

    def verify_api_call params, fitbit_api_method, auth_token, auth_secret
      api_error = "is not a valid Fitbit API method."
      api_error = get_error_message(params.keys, fitbit_api_method, auth_token, auth_secret) if fitbit_api_method
      raise "#{params['api-method']} " + api_error if api_error
    end

    def get_error_message params_keys, fitbit, auth_token, auth_secret
      error = missing_post_parameters_error fitbit[:post_parameters], params_keys
      error = missing_url_parameters_error fitbit[:url_parameters], params_keys unless error
      error = missing_auth_tokens_error fitbit[:auth_required], params_keys, auth_token, auth_secret unless error
      return error if error
    end

    def missing_post_parameters_error required, supplied
      return nil unless required
      required.each do |k,v|
        supplied_required = v & supplied unless k == 'required_if'
        case k
        when 'required'
          return missing_required_post_parameters_error(v, v-supplied) if supplied_required != v 
        when 'exclusive'
          supplied_length = supplied_required.length
          return missing_exclusive_post_parameters_error(v, supplied_required, supplied_length) if supplied_length != 1
        when 'one_required'
          return missing_one_required_post_parameters_error(v) if supplied_required.length < 1
        when 'required_if'
          return missing_required_if_post_parameters_error(v, supplied)
        end
      end
      nil
    end

    def missing_required_post_parameters_error required, missing
      "requires POST parameters #{required}. You're missing #{missing}."
    end

    def missing_exclusive_post_parameters_error required, supplied_required, supplied_length
      supplied_required_string = supplied_required.join(' AND ')
      return "requires one of these POST parameters: #{required}." if supplied_length < 1
      return "allows only one of these POST parameters #{required}. You used #{supplied_required_string}." if supplied_length > 1
    end

    def missing_one_required_post_parameters_error required
      return "requires at least one of the following POST parameters: #{required}."
    end

    def missing_required_if_post_parameters_error required, supplied
      required.each do |key,val|
        if supplied.include? key and !supplied.include? val
          return "requires POST parameter #{val} when you use POST parameter #{key}."
        end
      end
    end

    def missing_auth_tokens_error auth_required, params_keys, auth_token, auth_secret
      return nil unless auth_required
      no_auth_tokens = auth_token == "" or auth_secret == ""
      if auth_required == 'user-id' and no_auth_tokens and !params_keys.include? 'user-id'
        "requires user auth_token and auth_secret, unless you include [\"user-id\"]."
      elsif auth_required != 'user-id' and no_auth_tokens
        "requires user auth_token and auth_secret."
      end
    end

    def missing_url_parameters_error required, supplied
      return nil unless required
      if required.is_a? Hash
        return get_dynamic_url_error(required, supplied)
      elsif required & supplied != required
        return "requires #{required}. You're missing #{required-supplied}."
      end
      nil
    end

    def get_dynamic_url_error required, supplied
      required_hash = get_dynamic_url_parameters(required, supplied)
      return nil unless required_hash & supplied != required_hash
      error = "requires 1 of #{required.length} options: "
      required.keys.each_with_index do |k,i|
        error << "(#{i+1}) #{required[k]} "
      end
      error << "You supplied: #{supplied}"
    end

    def get_dynamic_url_parameters required, supplied
      required.keys.each { |k| return required[k] if supplied.include? k }
    end

    def build_request consumer_key, consumer_secret, auth_token, auth_secret
      fitbit = Fitbit::Api.new :fitbit, consumer_key, consumer_secret
      OAuth::AccessToken.new fitbit.consumer, auth_token, auth_secret
    end

    def build_url params, fitbit, http_method
      api = {
        :version            => params['api_version'] ? params['api_version'] : @@api_version,
        :url_resources      => get_url_resources(params, fitbit),
        :format             => params['response-format'] ? params['response-format'].downcase : 'xml',
        :post_parameters    => get_post_parameters(params, fitbit, http_method),
        :query              => uri_encode_query(params['query']),
      }

      "/#{api[:version]}/#{api[:url_resources]}.#{api[:format]}#{api[:query]}#{api[:post_parameters]}"
    end

    def get_url_resources params, fitbit
      params_keys = params.keys
      api_ids = get_url_parameters(fitbit[:url_parameters], params_keys) 
      api_resources = get_url_parameters(fitbit[:resources], params_keys)
      dynamic_url = add_ids(params, api_ids, api_resources, fitbit[:auth_required]) if api_ids or params['user-id']
      dynamic_url ||= api_resources
      dynamic_url.join("/")
    end

    def get_url_parameters required, supplied
      required = get_dynamic_url_parameters(required, supplied) if required.is_a? Hash
      required
    end

    def add_ids params, api_ids, api_resources, auth_required
      api_resources_copy = api_resources.dup
      api_resources_copy.each_with_index do |x, i|
        id = x.delete "<>"

        if x == '-' and auth_required == 'user-id' and params['user-id']
          api_resources_copy[i] = params['user-id']
        elsif id == 'collection-path' and params[id] == 'all'
          api_resources_copy.delete(x)
        elsif id == 'subscription-id' and params['collection-path'] != 'all'
          api_resources_copy[i] = params[id] + "-" + params['collection-path']
          api_resources_copy.delete('<collection-path>')
        elsif api_ids and api_ids.include? id and !api_ids.include? x 
          api_resources_copy[i] = params[id]
        end
      end
    end

    def get_post_parameters params, fitbit, http_method
      return nil if http_method != 'post' or is_subscription? params['api-method']
      not_post_parameters = [:request_headers, :url_parameters]
      ignore = ['api-method', 'response-format']
      not_post_parameters.each do |x|
        fitbit[x].each { |y| ignore.push(y) } if fitbit[x] 
      end
      post_parameters = params.select { |k,v| !ignore.include? k }

      "?" + OAuth::Helper.normalize(post_parameters)
    end
    
    def get_request_headers params, fitbit
      request_headers = fitbit[:request_headers]
      params.select { |k,v| request_headers.include? k }
    end

    def is_subscription? api_method
      api_method == 'api-create-subscription' or api_method == 'api-delete-subscription'
    end

    def uri_encode_query query
      query ? "?" + OAuth::Helper.normalize({ 'query' => query }) : ""
    end

    def send_api_request params, fitbit, access_token
      http_method = fitbit[:http_method]
      request_url = build_url(params, fitbit, http_method)
      request_headers = get_request_headers(params, fitbit) if fitbit[:request_headers]

      if http_method == 'get' or http_method == 'delete'
        access_token.request( http_method, "http://api.fitbit.com#{request_url}", request_headers )
      else
        access_token.request( http_method, "http://api.fitbit.com#{request_url}", "",  request_headers )
      end
    end

    @@api_version = 1

    @@fitbit_methods = {
      'api-accept-invite' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['accept'],
        },
        :url_parameters      => ['from-user-id'],
        :resources           => ['user', '-', 'friends', 'invitations', '<from-user-id>'],
      },
      'api-add-favorite-activity' => {
        :auth_required       => true,
        :http_method         => 'post',
        :url_parameters      => ['activity-id'],
        :resources           => ['user', '-', 'activities', 'favorite', '<activity-id>'],
      },
      'api-add-favorite-food' => {
        :auth_required       => true,
        :http_method         => 'post',
        :url_parameters      => ['food-id'],
        :resources           => ['user', '-', 'foods', 'log', 'favorite', '<food-id>'],
      },
      'api-browse-activities' => {
        :auth_required       => false,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['activities'],
      },
      'api-config-friends-leaderboard' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['hideMeFromLeaderboard'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'friends', 'leaderboard'],
      },
      'api-create-food' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['name', 'defaultFoodMeasurementUnitId', 'defaultServingSize', 'calories'],
        },
        :request_headers     => ['Accept-Locale'],
        :resources           => ['foods'],
      },
      'api-create-invite' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     =>  {
          'exclusive' => ['invitedUserEmail', 'invitedUserId'],
        },
        :resources           => ['user', '-', 'friends', 'invitations'],
      },
      'api-create-subscription' => {
        :auth_required       => true,
        :http_method         => 'post',
        :url_parameters      => ['collection-path', 'subscription-id'],
        :request_headers     => ['X-Fitbit-Subscriber-Id'],
        :resources           => ['user', '-', '<collection-path>', 'apiSubscriptions', '<subscription-id>', '<collection-path>']
      },
      'api-delete-activity-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['activity-log-id'],
        :resources           => ['user', '-', 'activities', '<activity-log-id>'],
      },
      'api-delete-blood-pressure-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['bp-log-id'],
        :resources           => ['user', '-', 'bp', '<bp-log-id>'],
      },
      'api-delete-body-fat-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['body-fat-log-id'],
        :resources           => ['user', '-', 'body', 'log', 'fat', '<body-fat-log-id>'],
      },
      'api-delete-body-weight-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['body-weight-log-id'],
        :resources           => ['user', '-', 'body', 'log', 'weight', '<body-weight-log-id>'],
      },
      'api-delete-favorite-activity' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['activity-id'],
        :resources           => ['user', '-', 'activities', 'favorite', '<activity-id>'],
      },
      'api-delete-favorite-food' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['food-id'],
        :resources           => ['user', '-', 'foods', 'log', 'favorite', '<food-id>'],
      },
      'api-delete-food-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['food-log-id'],
        :resources           => ['user', '-', 'foods', 'log', '<food-log-id>'],
      },
      'api-delete-heart-rate-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['heart-log-id'],
        :resources           => ['user', '-', 'heart', '<heart-log-id>'],
      },
      'api-delete-sleep-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['sleep-log-id'],
        :resources           => ['user', '-', 'sleep', '<sleep-log-id>'],
      },
      'api-delete-subscription' => {
        :auth_required       => 'user-id',
        :http_method         => 'delete',
        :url_parameters      => ['collection-path', 'subscription-id'],
        :resources           => ['user', '-', '<collection-path>', 'apiSubscriptions', '<subscription-id>', '<collection-path>']
      },
      'api-delete-water-log' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['water-log-id'],
        :resources           => ['user', '-', 'foods', 'log', 'water', '<water-log-id>'],
      },
      'api-devices-add-alarm' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['time', 'enabled', 'recurring', 'weekDays'],
        },
        :request_headers     => ['Accept-Language'],
        :url_parameters      => ['device-id'],
        :resources           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms'],
      },
      'api-devices-delete-alarm' => {
        :auth_required       => true,
        :http_method         => 'delete',
        :url_parameters      => ['device-id', 'alarm-id'],
        :resources           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms', '<alarm-id>'],
      },
      'api-devices-get-alarms' => {
        :auth_required       => true,
        :http_method         => 'get',
        :url_parameters      => ['device-id'],
        :resources           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms'],
      },
      'api-devices-update-alarm' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['time', 'enabled', 'recurring', 'weekDays', 'snoozeLength', 'snoozeCount'],
        },
        :request_headers     => ['Accept-Language'],
        :url_parameters      => ['device-id', 'alarm-id'],
        :resources           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms', '<alarm-id>'],
      },
      'api-get-activities' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale', 'Accept-Language'],
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'activities', 'date', '<date>'],
      },
      'api-get-activity' => {
        :auth_required       => false,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :url_parameters      => ['activity-id'],
        :resources           => ['activities', '<activity-id>'],
      },
      'api-get-activity-daily-goals' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'activities', 'goals', 'daily'],
      },
      'api-get-activity-stats' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'activities'],
      },
      'api-get-activity-weekly-goals' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'activities', 'goals', 'weekly'],
      },
      'api-get-badges' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'badges'],
      },
      'api-get-blood-pressure' => {
        :auth_required       => true,
        :http_method         => 'get',
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'bp', 'date', '<date>'],
      },
      'api-get-body-fat' => {
        :auth_required       => true,
        :http_method         => 'get',
        :url_parameters      => {
          'date'      => ['date'],
          'end-date'  => ['base-date', 'end-date'],
          'period'    => ['base-date', 'period'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => {
          'date'      => ['user', '-', 'body', 'log', 'fat', 'date', '<date>'],
          'end-date'  => ['user', '-', 'body', 'log', 'fat', 'date', '<base-date>', '<end-date>'],
          'period'    => ['user', '-', 'body', 'log', 'fat', 'date', '<base-date>', '<period>'],
        }
      },
      'api-get-body-fat-goal' => {
        :auth_required       => true,
        :http_method         => 'get',
        :resources           => ['user', '-', 'body', 'log', 'fat', 'goal'],
      },
      'api-get-body-measurements' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'body', 'date', '<date>'],
      },
      'api-get-body-weight' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => {
          'date'      => ['date'],
          'end-date'  => ['base-date', 'end-date'],
          'period'    => ['base-date', 'period'],
        },
        :resources           => {
          'date'      => ['user', '-', 'body', 'log', 'weight', 'date', '<date>'],
          'end-date'  => ['user', '-', 'body', 'log', 'weight', 'date', '<base-date>', '<end-date>'],
          'period'    => ['user', '-', 'body', 'log', 'weight', 'date', '<base-date>', '<period>'],
        }
      },
      'api-get-body-weight-goal' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'body', 'log', 'weight', 'goal'],
      },
      'api-get-device' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :url_parameters      => ['device-id'],
        :resources           => ['user', '-', 'devices', '<device-id>'],
      },
      'api-get-devices' => {
        :auth_required       => true,
        :http_method         => 'get',
        :resources           => ['user', '-', 'devices'],
      },
      'api-get-favorite-activities' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'activities', 'favorite'],
      },
      'api-get-favorite-foods' => {
        :auth_required       => true,
        :http_method         => 'get',
        :resources           => ['user', '-', 'foods', 'log', 'favorite'],
      },
      'api-get-food' => {
        :auth_required       => false,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :url_parameters      => ['food-id'],
        :resources           => ['foods', '<food-id>'],
      },
      'api-get-food-goals' => {
        :auth_required       => true,
        :http_method         => 'get',
        :resources           => ['user', '-', 'foods', 'log', 'goal'],
      },
      'api-get-foods' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'foods', 'log', 'date', '<date>'],
      },
      'api-get-food-units' => {
        :auth_required       => false,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['foods', 'units'],
      },
      'api-get-frequent-activities' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale', 'Accept-Language'],
        :resources           => ['user', '-', 'activities', 'frequent'],
      },
      'api-get-frequent-foods' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'foods', 'log', 'frequent'],
      },
      'api-get-friends' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'friends'],
      },
      'api-get-friends-leaderboard' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'friends', 'leaderboard'],
      },
      'api-get-glucose' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'glucose', 'date', '<date>'],
      },
      'api-get-heart-rate' => {
        :auth_required       => true,
        :http_method         => 'get',
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'heart', 'date', '<date>'],
      },
      'api-get-intraday-time-series' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => {
          'date'             => ['resource-path', 'date'],
          'start-time'       => ['resource-path', 'date', 'start-time', 'end-time'],
        },
        :resources           => {
          'date'             => ['user', '-', '<resource-path>', 'date', '<date>'],
          'start-time'       => ['user', '-', '<resource-path>', 'date', '<date>', '<start-time>', '<end-time>'],
        },
      },
      'api-get-invites' => {
        :auth_required       => true,
        :http_method         => 'get',
        :resources           => ['user', '-', 'friends', 'invitations'],
      },
      'api-get-meals' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'meals'],
      },
      'api-get-recent-activities' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale', 'Accept-Language'],
        :resources           => ['user', '-', 'activities', 'recent'],
      },
      'api-get-recent-foods' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'foods', 'log', 'recent'],
      },
      'api-get-sleep' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'sleep', 'date', '<date>'],
      },
      'api-get-time-series' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => {
          'end-date'  => ['base-date', 'end-date', 'resource-path'],
          'period'    => ['base-date', 'period', 'resource-path'],
        },
        :resources           => {
          'end-date'  => ['user', '-', '<resource-path>', 'date', '<base-date>', '<end-date>'],
          'period'    => ['user', '-', '<resource-path>', 'date', '<base-date>', '<period>'],
        },
      },
      'api-get-user-info' => {
        :auth_required       => 'user-id',
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'profile'],
      },
      'api-get-water' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Language'],
        :url_parameters      => ['date'],
        :resources           => ['user', '-', 'foods', 'log', 'water', 'date', '<date>'],
      },
      'api-log-activity' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'exclusive' => ['activityId', 'activityName'], 
          'required'  => ['startTime', 'durationMillis', 'date'],
          'required_if'  => { 'activityName' => 'manualCalories' },
        },
        :request_headers     => ['Accept-Locale', 'Accept-Language'],
        :resources           => ['user', '-', 'activities'],
      },
      'api-log-blood-pressure' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['systolic', 'diastolic', 'date'],
        },
        :resources           => ['user', '-', 'bp'],
      },
      'api-log-body-fat' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['fat', 'date'],
        },
        :resources           => ['user', '-', 'body', 'log', 'fat'],
      },
      'api-log-body-measurements' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['date'],
          'one_required' => ['bicep','calf','chest','fat','forearm','hips','neck','thigh','waist','weight'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'body'],
      },
      'api-log-body-weight' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['weight', 'date'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'body', 'log', 'weight'],
      },
      'api-log-food' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'exclusive' => ['foodId', 'foodName'], 
          'required'  => ['mealTypeId', 'unitId', 'amount', 'date'],
        },
        :request_headers     => ['Accept-Locale'],
        :resources           => ['user', '-', 'foods', 'log'],
      },
      'api-log-glucose' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'exclusive' => ['hbac1c', 'tracker'], 
          'required'  => ['date'],
          'required_if'  => { 'tracker' => 'glucose' },
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'glucose'],
      },
      'api-log-heart-rate' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['tracker', 'heartRate', 'date'],
        },
        :resources           => ['user', '-', 'heart'],
      },
      'api-log-sleep' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['startTime', 'duration', 'date'],
        },
        :resources           => ['user', '-', 'sleep'],
      },
      'api-log-water' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['amount', 'date'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'foods', 'log', 'water'],
      },
      'api-search-foods' => {
        :auth_required       => true,
        :http_method         => 'get',
        :request_headers     => ['Accept-Locale'],
        :url_parameters      => ['query'],
        :resources           => ['foods', 'search'],
      },
      'api-update-activity-daily-goals' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'one_required' => ['caloriesOut','activeMinutes','floors','distance','steps'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'activities', 'goals', 'daily'],
      },
      'api-update-activity-weekly-goals' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'one_required' => ['steps','distance','floors'],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'activities', 'goals', 'weekly'],
      },
      'api-update-fat-goal' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['fat'],
        },
        :resources           => ['user', '-', 'body', 'log', 'fat', 'goal'],
      },
      'api-update-food-goals' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'exclusive' => ['calories', 'intensity'],
        },
        :request_headers     => ['Accept-Locale', 'Accept-Language'],
        :resources           => ['user', '-', 'foods', 'log', 'goal'],
      },
      'api-update-user-info' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'one_required' => [
          'gender','birthday','height','nickname','aboutMe','fullname','country','state','city',
          'strideLengthWalking','strideLengthRunning','weightUnit','heightUnit','waterUnit','glucoseUnit',
          'timezone','foodsLocale','locale','localeLang','localeCountry'
          ],
        },
        :request_headers     => ['Accept-Language'],
        :resources           => ['user', '-', 'profile'],
      },
      'api-update-weight-goal' => {
        :auth_required       => true,
        :http_method         => 'post',
        :post_parameters     => {
          'required' => ['startDate', 'startWeight'],
        },
        :resources           => ['user', '-', 'body', 'log', 'weight', 'goal'],
      },
    }

  end
end
