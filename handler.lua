local config = require('config')
local domain = require('domain')
local target = require('target')

local handler = {
  err_not_found = "not_found",
  err_redirect = "redirect",
  err_internal_server_error = "internal_server_error",

  cache = ngx.shared.rise
}

function handler.handle(host, path) -- returns (prefix, target, err, err_log)
  local prefix_cache_key = host..":pfx"
  local prefix = handler.cache:get(prefix_cache_key)
  if not prefix then
    -- cache miss for HOST:prefix
    local meta, err = domain.get_meta(host)
    if err then
      return nil, nil, handler.err_not_found, "Failed to fetch metadata for "..host.." due to "..err
    end

    if not meta.prefix then
      return nil, nil, handler.internal_server_error, "meta.json for "..host.." did not contain prefix"
    end

    prefix = meta.prefix
    handler.cache:set(host..":pfx", prefix)
  end

  local webroot_uri = config.s3_host.."/deployments/"..prefix.."/webroot"
  local target_path_cache_key = prefix..":"..path..":tgt"
  local should_redirect_cache_key = prefix..":"..path..":rdr"
  local target_path, should_redirect = handler.cache:get(target_path_cache_key), handler.cache:get(should_redirect_cache_key)

  if not target_path or should_redirect == nil then -- should_redirect is boolean
    local err
    target_path, should_redirect, err = target.resolve(path, webroot_uri, true)
    if err or not target_path then
      return nil, nil, handler.internal_server_error, "could not resolve "..host..path
    end

    handler.cache:set(target_path_cache_key, target_path)
    handler.cache:set(should_redirect_cache_key, should_redirect)
  end

  if should_redirect then
    return prefix, target_path, handler.err_redirect, nil
  end

  return prefix, webroot_uri..target_path, nil, nil
end

return handler
