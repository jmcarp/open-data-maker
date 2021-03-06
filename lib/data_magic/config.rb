module DataMagic
  class Config
    attr_reader :data_path, :data, :global_mapping, :files, :s3, :api_endpoints
    attr_accessor :page_size

    def initialize(options = {})
      @api_endpoints = {}
      @files = []
      @global_mapping = {}
      @page_size = DataMagic::DEFAULT_PAGE_SIZE
      @s3 = options[:s3]

      @data_path = options[:data_path] || ENV['DATA_PATH']
      if @data_path.nil? or @data_path.empty?
        @data_path = DEFAULT_PATH
      end

      load_datayaml
    end


    def self.init(s3 = nil)
      logger.info "Config.init #{s3.inspect}"
      @s3 = s3
      Config.load
    end

    def clear_all
      unless @data.nil? or @data.empty?
        logger.info "Config.clear_all: deleting index '#{scoped_index_name}'"
        Stretchy.delete scoped_index_name
        DataMagic.client.indices.clear_cache
      end
    end

    def self.logger=(new_logger)
      @logger = new_logger
    end
    
    def self.logger
      @logger ||= Logger.new("log/#{ENV['RACK_ENV'] || 'development'}.log")
    end

    def logger
      Config.logger
    end

    def additional_data_for_file(fname)
      @data['files'][fname]['add']
    end

    def scoped_index_name(index_name = nil)
      index_name ||= @data['index']
      env = ENV['RACK_ENV']
      "#{env}-#{index_name}"
    end

    # returns an array of api_endpoints
    # list of strings
    def api_endpoint_names
      @api_endpoints.keys
    end


    def find_index_for(api)
      api_info = @api_endpoints[api] || {}
      api_info[:index]
    end

    # update current configuration document in the index, if needed
    # return whether the current config was new and required an update
    def update_indexed_config
      updated = false
      old_config = nil
      index_name = scoped_index_name
      logger.info "looking for: #{index_name}"
      if DataMagic.client.indices.exists? index: index_name
        begin
          response = DataMagic.client.get index: index_name, type: 'config', id: 1
          old_config = response["_source"]
        rescue Elasticsearch::Transport::Transport::Errors::NotFound
          logger.debug "no prior index configuration"
        end
      else
        logger.debug "creating index"
        DataMagic.create_index(index_name)  ## DataMagic::Index.create ?
      end
      logger.debug "old_config (from es): #{old_config.inspect}"
      logger.debug "new_config (just loaded from data.yaml): #{@data.inspect}"
      if old_config.nil? || old_config["version"] != @data["version"]
        logger.debug "--------> adding config to index: #{@data.inspect}"
        DataMagic.client.index index: index_name, type:'config', id: 1, body: @data
        updated = true
      end
      updated
    end


    # reads a file or s3 object, returns a string
    # path follows URI pattern
    # could be
    #   s3://username:password@bucket_name/path
    #   s3://bucket_name/path
    #   s3://bucket_name
    #   a local path like: './data'
    def read_path(path)
      uri = URI(path)
      scheme = uri.scheme
      case scheme
        when nil
          File.read(uri.path)
        when "s3"
          key = uri.path
          key[0] = ''  # remove initial /
          response = @s3.get_object(bucket: uri.hostname, key: key)
          response.body.read
        else
          raise ArgumentError, "unexpected scheme: #{scheme}"
      end
    end


    def load_datayaml(directory_path = nil)
      logger.debug "---- Config.load -----"
      if directory_path.nil? or directory_path.empty?
        directory_path = data_path
      end

      if @data and @data['data_path'] == directory_path
        logger.debug "already loaded, nothing to do!"
      else
        logger.debug "load config #{directory_path.inspect}"
        @files = []
        config_text = read_path("#{directory_path}/data.yaml")
        @data = YAML.load(config_text)
        logger.debug "config: #{@data.inspect}"
        index = @data['index'] || 'general'
        endpoint = @data['api'] || 'data'
        @global_mapping = @data['global_mapping'] || {}
        @api_endpoints[endpoint] = {index: index}

        file_config = @data['files']
        logger.debug "file_config: #{file_config.inspect}"
        if file_config.nil?
          logger.debug "no files found"
        else
          fnames = @data["files"].keys

          fnames.each do |fname|
            @data["files"][fname] ||= {}
            @files << File.join(directory_path, fname)
          end
        end
        # keep track of where we loaded our data, so we can avoid loading again
        @data['data_path'] = directory_path
        @data_path = directory_path  # make sure this is set, in case it changed
      end
      scoped_index_name
    end

  end # class Config
end # module DataMagic
