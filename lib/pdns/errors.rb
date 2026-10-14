module Pdns
  class GeneralError < RuntimeError; end
  class ActionRefused < RuntimeError; end

  class AuthenticationFailed < RuntimeError; end
  class ConnectionFailed < GeneralError; end
  class ConnectionTimeout < GeneralError; end

  class MissingParameter < RuntimeError; end
  class InvalidParameter < RuntimeError; end

  class UnknownObject < RuntimeError; end
  class NotImplemented < RuntimeError; end

end
