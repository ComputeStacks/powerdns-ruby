module Pdns
  class GeneralError < RuntimeError; end
  class ActionRefused < RuntimeError; end

  class AuthenticationFailed < RuntimeError; end
  class ConnectionFailed < RuntimeError; end
  class ConnectionTimeout < RuntimeError; end

  class MissingParameter < RuntimeError; end
  class InvalidParameter < RuntimeError; end

  class UnknownObject < RuntimeError; end
  class NotImplemented < RuntimeError; end

end
