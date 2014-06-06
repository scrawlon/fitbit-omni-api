require 'omniauth-fitbit'

module Fitbit
  class Api < OmniAuth::Strategies::OAuth
    class << self 
      def request consumer_key, consumer_secret, params, auth_token="", auth_secret=""
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
        error = get_error_message(params.keys, fitbit_api_method, auth_token, auth_secret)
        raise "#{params['api-method']} " + error if error
      end

      def get_error_message params_keys, fitbit_api_method, auth_token, auth_secret
        error = "is not a valid Fitbit API method." unless fitbit_api_method
        error = missing_post_parameters_error fitbit_api_method[:post_parameters], params_keys unless error
        error = missing_url_parameters_error fitbit_api_method[:url_parameters], params_keys unless error
        error = missing_auth_tokens_error fitbit_api_method[:auth_required], params_keys, auth_token, auth_secret unless error
        error ||= nil
      end

      def missing_post_parameters_error required, supplied
        return nil unless required
        required.each do |k,v|
          supplied_required = v & supplied unless k == 'required_if'
          case k
          when 'required'
            error = missing_required_post_parameters_error(v, supplied, supplied_required)
          when 'exclusive'
            error = missing_exclusive_post_parameters_error(v, supplied_required)
          when 'one_required'
            error = missing_one_required_post_parameters_error(v, supplied_required)
          when 'required_if'
            error = missing_required_if_post_parameters_error(v, supplied)
          end
          return error if error
        end
        nil
      end

      def missing_required_post_parameters_error required, supplied, supplied_required
        "requires POST parameters #{required}. You're missing #{required-supplied}." if supplied_required != required 
      end

      def missing_exclusive_post_parameters_error required, supplied_required
        total_supplied = supplied_required.length
        return nil if total_supplied == 1
        if total_supplied < 1
          "requires one of these POST parameters: #{required}." 
        elsif total_supplied > 1
          "allows only one of these POST parameters: #{required}. You used #{supplied_required.join(' AND ')}." 
        end
      end

      def missing_one_required_post_parameters_error required, supplied_required
        "requires at least one of the following POST parameters: #{required}." if supplied_required.length < 1
      end

      def missing_required_if_post_parameters_error required, supplied
        required.each do |k,v|
          return "requires POST parameter #{v} when you use POST parameter #{k}." if supplied.include? k and !supplied.include? v
        end
      end

      def missing_auth_tokens_error auth_required, params_keys, auth_token, auth_secret
        return nil unless auth_required
        no_auth_tokens = auth_token == "" or auth_secret == ""
        if no_auth_tokens and auth_required == 'user-id'
          "requires user auth_token and auth_secret, unless you include [\"user-id\"]." unless params_keys.include? 'user-id'
        elsif no_auth_tokens
          "requires user auth_token and auth_secret."
        end
      end

      def missing_url_parameters_error required, supplied
        return nil unless required
        if required.is_a? Hash
          get_dynamic_url_error(required, supplied)
        else
          required = get_url_parameters_variables(required)
          required - supplied != [] ? "requires #{required}. You're missing #{required-supplied}." : nil
        end
      end

      def get_dynamic_url_error required, supplied
        return nil unless missing_dynamic_url_parameters?(required, supplied)
        required = required.dup
        required.delete('optional')
        options = required.keys.map.with_index(1) { |x,i| "(#{i}) #{get_url_parameters_variables(required[x])}" }.join(' ')
        "requires 1 of #{required.length} options: #{options}. You supplied: #{supplied}."
      end

      def missing_dynamic_url_parameters? required, supplied
        required = get_dynamic_url_parameters(required, supplied)
        required = get_url_parameters_variables(required) if required
        required & supplied != required  
      end

      def get_dynamic_url_parameters required, supplied
        optional = get_optional_url_parameters(required, supplied)
        required.keys.each { |k| return required[k] + optional if supplied.include? k }
        nil
      end

      def get_url_parameters_variables url_parameters
        url_parameters.select { |x| x.include? "<" }.map { |x| x.delete "<>" } if has_url_variables? url_parameters
      end

      def has_url_variables? url_parameters
        url_parameters.each{ |x| return true if x.include? "<" }
      end

      def build_request consumer_key, consumer_secret, auth_token, auth_secret
        fitbit = Fitbit::Api.new :fitbit, consumer_key, consumer_secret
        OAuth::AccessToken.new fitbit.consumer, auth_token, auth_secret
      end

      def get_url_resources params, fitbit_api_method
        url_parameters = get_url_parameters(fitbit_api_method[:url_parameters], params.keys)
        if has_url_variables? url_parameters or params['user-id'] 
          url_parameters = insert_dynamic_url_parameters(params, url_parameters, fitbit_api_method[:auth_required])
        end
        url_parameters.join("/")
      end

      def get_url_parameters required, supplied
        required = get_dynamic_url_parameters(required, supplied) if required.is_a? Hash
        required
      end

      def get_optional_url_parameters required, supplied
        return [] unless required['optional']
        optional = required['optional'].select { |k,v| supplied.include? k }.values.flatten
      end

      def insert_dynamic_url_parameters params, url_parameters, auth_required
        url_parameters.map do |x|
          url_variable = x.delete "<>"

          if is_subscription_variable? url_variable
            insert_subscription_variable(params, url_variable)
          elsif x == '-'
            insert_user_id(auth_required, params['user-id'])
          elsif params.include? url_variable and !params.include? x
            params[url_variable]
          else
            x
          end
        end - [nil]
      end

      def is_subscription_variable? url_variable
        subscription_variables = ['subscription-id', 'collection-path']
        subscription_variables.include? url_variable
      end

      def insert_subscription_variable params, url_variable
        if params['collection-path'] == 'all'
          url_variable == 'subscription-id' ? params[url_variable] : nil
        else
          url_variable == 'subscription-id' ? "#{params[url_variable]}-#{params['collection-path']}" : params[url_variable]
        end
      end

      def insert_user_id auth_required, user_id
        (auth_required == 'user-id' and user_id) ? user_id : '-'
      end

      def get_post_parameters params, fitbit, http_method
        return nil if http_method != 'post' or is_subscription? params['api-method']
        post_parameters = params.select { |k,v| fitbit[:post_parameters].values.flatten.include? k }
        "?" + OAuth::Helper.normalize(post_parameters)
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
        request_headers = get_request_headers(params, fitbit[:request_headers])

        if http_method == 'get' or http_method == 'delete'
          access_token.request( http_method, "http://api.fitbit.com#{request_url}", request_headers )
        else
          access_token.request( http_method, "http://api.fitbit.com#{request_url}", "", request_headers )
        end
      end

      def build_url params, fitbit_api_method, http_method
        api = {
          :version            => params['api_version'] ? params['api_version'] : @@api_version,
          :url_resources      => get_url_resources(params, fitbit_api_method),
          :response_format    => params['response-format'] ? params['response-format'].downcase : 'xml',
          :post_parameters    => get_post_parameters(params, fitbit_api_method, http_method),
          :query              => uri_encode_query(params['query']),
        }
        "/#{api[:version]}/#{api[:url_resources]}.#{api[:response_format]}#{api[:query]}#{api[:post_parameters]}"
      end
      
      def get_request_headers params, request_headers
        return nil unless request_headers
        params.select { |k,v| request_headers.include? k }
      end

      @@api_version = 1

      @@fitbit_methods = {
        'api-accept-invite' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['accept'],
          },
          :url_parameters           => ['user', '-', 'friends', 'invitations', '<from-user-id>'],
        },
        'api-add-favorite-activity' => {
          :auth_required       => true,
          :http_method         => 'post',
          :url_parameters           => ['user', '-', 'activities', 'favorite', '<activity-id>'],
        },
        'api-add-favorite-food' => {
          :auth_required       => true,
          :http_method         => 'post',
          :url_parameters           => ['user', '-', 'foods', 'log', 'favorite', '<food-id>'],
        },
        'api-browse-activities' => {
          :auth_required       => false,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['activities'],
        },
        'api-config-friends-leaderboard' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['hideMeFromLeaderboard'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'friends', 'leaderboard'],
        },
        'api-create-food' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['name', 'defaultFoodMeasurementUnitId', 'defaultServingSize', 'calories'],
            'optional' => ['formType', 'description'],
          },
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['foods'],
        },
        'api-create-invite' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     =>  {
            'exclusive' => ['invitedUserEmail', 'invitedUserId'],
          },
          :url_parameters           => ['user', '-', 'friends', 'invitations'],
        },
        'api-create-subscription' => {
          :auth_required       => true,
          :http_method         => 'post',
          :request_headers     => ['X-Fitbit-Subscriber-Id'],
          :url_parameters           => ['user', '-', '<collection-path>', 'apiSubscriptions', '<subscription-id>']
        },
        'api-delete-activity-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'activities', '<activity-log-id>'],
        },
        'api-delete-blood-pressure-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'bp', '<bp-log-id>'],
        },
        'api-delete-body-fat-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'body', 'log', 'fat', '<body-fat-log-id>'],
        },
        'api-delete-body-weight-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'body', 'log', 'weight', '<body-weight-log-id>'],
        },
        'api-delete-favorite-activity' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'activities', 'favorite', '<activity-id>'],
        },
        'api-delete-favorite-food' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'foods', 'log', 'favorite', '<food-id>'],
        },
        'api-delete-food-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'foods', 'log', '<food-log-id>'],
        },
        'api-delete-heart-rate-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'heart', '<heart-log-id>'],
        },
        'api-delete-sleep-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'sleep', '<sleep-log-id>'],
        },
        'api-delete-subscription' => {
          :auth_required       => 'user-id',
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', '<collection-path>', 'apiSubscriptions', '<subscription-id>']
        },
        'api-delete-water-log' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'foods', 'log', 'water', '<water-log-id>'],
        },
        'api-devices-add-alarm' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['time', 'enabled', 'recurring', 'weekDays'],
            'optional' => ['label', 'snoozeLength', 'snoozeCount', 'vibe'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms'],
        },
        'api-devices-delete-alarm' => {
          :auth_required       => true,
          :http_method         => 'delete',
          :url_parameters           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms', '<alarm-id>'],
        },
        'api-devices-get-alarms' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms'],
        },
        'api-devices-update-alarm' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['time', 'enabled', 'recurring', 'weekDays', 'snoozeLength', 'snoozeCount'],
            'optional' => ['label', 'vibe'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'devices', 'tracker', '<device-id>', 'alarms', '<alarm-id>'],
        },
        'api-get-activities' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale', 'Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'date', '<date>'],
        },
        'api-get-activity' => {
          :auth_required       => false,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['activities', '<activity-id>'],
        },
        'api-get-activity-daily-goals' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'goals', 'daily'],
        },
        'api-get-activity-stats' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'activities'],
        },
        'api-get-activity-weekly-goals' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'goals', 'weekly'],
        },
        'api-get-badges' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'badges'],
        },
        'api-get-blood-pressure' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'bp', 'date', '<date>'],
        },
        'api-get-body-fat' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => {
            'date'      => ['user', '-', 'body', 'log', 'fat', 'date', '<date>'],
            'end-date'  => ['user', '-', 'body', 'log', 'fat', 'date', '<base-date>', '<end-date>'],
            'period'    => ['user', '-', 'body', 'log', 'fat', 'date', '<base-date>', '<period>'],
          }
        },
        'api-get-body-fat-goal' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'body', 'log', 'fat', 'goal'],
        },
        'api-get-body-measurements' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'body', 'date', '<date>'],
        },
        'api-get-body-weight' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => {
            'date'      => ['user', '-', 'body', 'log', 'weight', 'date', '<date>'],
            'end-date'  => ['user', '-', 'body', 'log', 'weight', 'date', '<base-date>', '<end-date>'],
            'period'    => ['user', '-', 'body', 'log', 'weight', 'date', '<base-date>', '<period>'],
          }
        },
        'api-get-body-weight-goal' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'body', 'log', 'weight', 'goal'],
        },
        'api-get-device' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'devices', '<device-id>'],
        },
        'api-get-devices' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'devices'],
        },
        'api-get-favorite-activities' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'activities', 'favorite'],
        },
        'api-get-favorite-foods' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'foods', 'log', 'favorite'],
        },
        'api-get-food' => {
          :auth_required       => false,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['foods', '<food-id>'],
        },
        'api-get-food-goals' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'foods', 'log', 'goal'],
        },
        'api-get-foods' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'date', '<date>'],
        },
        'api-get-food-units' => {
          :auth_required       => false,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['foods', 'units'],
        },
        'api-get-frequent-activities' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale', 'Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'frequent'],
        },
        'api-get-frequent-foods' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'frequent'],
        },
        'api-get-friends' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'friends'],
        },
        'api-get-friends-leaderboard' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'friends', 'leaderboard'],
        },
        'api-get-glucose' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'glucose', 'date', '<date>'],
        },
        'api-get-heart-rate' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'heart', 'date', '<date>'],
        },
        'api-get-intraday-time-series' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => {
            'end-date'  => ['user', '-', '<resource-path>', 'date', '<base-date>', '<end-date>'],
            'period'    => ['user', '-', '<resource-path>', 'date', '<base-date>', '<period>'],
            'optional'  => {
              'detail-level'  => [ '<detail-level>' ],
              'start-time'    => ['time', '<start-time>', '<end-time>']
            },
          },
        },
        'api-get-invites' => {
          :auth_required       => true,
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'friends', 'invitations'],
        },
        'api-get-meals' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'meals'],
        },
        'api-get-recent-activities' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale', 'Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'recent'],
        },
        'api-get-recent-foods' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'recent'],
        },
        'api-get-sleep' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :url_parameters           => ['user', '-', 'sleep', 'date', '<date>'],
        },
        'api-get-time-series' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => {
            'end-date'  => ['user', '-', '<resource-path>', 'date', '<base-date>', '<end-date>'],
            'period'    => ['user', '-', '<resource-path>', 'date', '<base-date>', '<period>'],
          },
        },
        'api-get-user-info' => {
          :auth_required       => 'user-id',
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'profile'],
        },
        'api-get-water' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'water', 'date', '<date>'],
        },
        'api-log-activity' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'exclusive' => ['activityId', 'activityName'], 
            'required'  => ['startTime', 'durationMillis', 'date'],
            'required_if'  => { 'activityName' => 'manualCalories' },
            'optional'  => ['distanceUnit'],
          },
          :request_headers     => ['Accept-Locale', 'Accept-Language'],
          :url_parameters           => ['user', '-', 'activities'],
        },
        'api-log-blood-pressure' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['systolic', 'diastolic', 'date'],
            'optional' => ['time'],
          },
          :url_parameters           => ['user', '-', 'bp'],
        },
        'api-log-body-fat' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['fat', 'date'],
            'optional' => ['time'],
          },
          :url_parameters           => ['user', '-', 'body', 'log', 'fat'],
        },
        'api-log-body-measurements' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['date'],
            'one_required' => ['bicep','calf','chest','fat','forearm','hips','neck','thigh','waist','weight'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'body'],
        },
        'api-log-body-weight' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['weight', 'date'],
            'optional' => ['time'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'body', 'log', 'weight'],
        },
        'api-log-food' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'exclusive' => ['foodId', 'foodName'], 
            'required'  => ['mealTypeId', 'unitId', 'amount', 'date'],
            'optional'  => ['brandName', 'calories', 'favorite'],
          },
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['user', '-', 'foods', 'log'],
        },
        'api-log-glucose' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'exclusive' => ['hbac1c', 'tracker'], 
            'required'  => ['date'],
            'required_if'  => { 'tracker' => 'glucose' },
            'optional' => ['time'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'glucose'],
        },
        'api-log-heart-rate' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['tracker', 'heartRate', 'date'],
            'optional' => ['time'],
          },
          :url_parameters           => ['user', '-', 'heart'],
        },
        'api-log-sleep' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['startTime', 'duration', 'date'],
          },
          :url_parameters           => ['user', '-', 'sleep'],
        },
        'api-log-water' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['amount', 'date'],
            'optional' => ['unit'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'water'],
        },
        'api-search-foods' => {
          :auth_required       => true,
          :http_method         => 'get',
          :request_headers     => ['Accept-Locale'],
          :url_parameters           => ['foods', 'search'],
        },
        'api-update-activity-daily-goals' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'one_required' => ['caloriesOut','activeMinutes','floors','distance','steps'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'goals', 'daily'],
        },
        'api-update-activity-weekly-goals' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'one_required' => ['steps','distance','floors'],
          },
          :request_headers     => ['Accept-Language'],
          :url_parameters           => ['user', '-', 'activities', 'goals', 'weekly'],
        },
        'api-update-fat-goal' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['fat'],
          },
          :url_parameters           => ['user', '-', 'body', 'log', 'fat', 'goal'],
        },
        'api-update-food-goals' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'exclusive' => ['calories', 'intensity'],
            'optional'  => ['personalized'],
          },
          :request_headers     => ['Accept-Locale', 'Accept-Language'],
          :url_parameters           => ['user', '-', 'foods', 'log', 'goal'],
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
          :url_parameters           => ['user', '-', 'profile'],
        },
        'api-update-weight-goal' => {
          :auth_required       => true,
          :http_method         => 'post',
          :post_parameters     => {
            'required' => ['startDate', 'startWeight'],
            'optional' => ['weight'],
          },
          :url_parameters           => ['user', '-', 'body', 'log', 'weight', 'goal'],
        },
      }
    end
  end
end
