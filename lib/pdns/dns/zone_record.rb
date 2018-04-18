module Pdns::Dns
  class ZoneRecord

    attr_accessor :id,
                  :type,
                  :ip,
                  :name,
                  :hostname,
                  :priority,
                  :port,
                  :weight,
                  :value,
                  :serial,
                  :primary_dns,
                  :retry,
                  :refresh,
                  :expire,
                  :email,
                  :ttl,
                  :zone_id

    def initialize(client, id, zone_id, data = {})
      self.ttl = 3600
      load!(data) unless data.empty?
    end

    def load!(data)
      self.name = data['name']
      self.ttl = data['ttl'] if data['ttl']
      self.type = data['type']
      case self.type
      when 'CNAME', 'NS'
        self.hostname = data['content']
      when 'A', 'AAAA'
        self.ip = data['content']
      when 'MX'
        self.priority = data['content'].split(' ').first.to_i
        self.hostname = data['content'].split(' ').last.strip
      when 'NS'
        self.hostname = data['content']
      else # TXT, SOA, PTR
        self.value = data['content']
      end
    end

    # Format record value specifically for PowerDNS.
    def raw_value
      case self.type
      when 'CNAME', 'NS'
        self.hostname
      when 'A', 'AAAA'
        self.ip
      when 'MX'
        "#{self.priority} #{self.hostname}"
      else # TXT, PTR
        self.value
      end
    end

  end
end
