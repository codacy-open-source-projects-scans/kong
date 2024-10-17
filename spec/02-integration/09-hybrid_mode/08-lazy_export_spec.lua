local helpers = require "spec.helpers"

local admin_client

local function cp(strategy, inc_sync)
  helpers.get_db_utils(strategy) -- make sure the DB is fresh n' clean
  assert(helpers.start_kong({
    role = "control_plane",
    cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
    database = strategy,
    cluster_listen = "127.0.0.1:9005",
    nginx_conf = "spec/fixtures/custom_nginx.template",
    -- additional attributes for PKI:
    cluster_mtls = "pki",
    cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
    cluster_incremental_sync = inc_sync,
  }))
  admin_client = assert(helpers.admin_client())
end

local n = 0
local function touch_config()
  n = n + 1
  assert(admin_client:send({
    method = "POST",
    path = "/services",
    body = {
      name = "test" .. n,
      host = "localhost",
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  }))
end

local function json_dp(inc_sync)
  assert(helpers.start_kong({
    role = "data_plane",
    database = "off",
    prefix = "dp1",
    cluster_cert = "spec/fixtures/ocsp_certs/kong_data_plane.crt",
    cluster_cert_key = "spec/fixtures/ocsp_certs/kong_data_plane.key",
    cluster_control_plane = "127.0.0.1:9005",
    proxy_listen = "0.0.0.0:9002",
    -- additional attributes for PKI:
    cluster_mtls = "pki",
    cluster_server_name = "kong_clustering",
    cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
    cluster_incremental_sync = inc_sync,
  }))
end


for _, inc_sync in ipairs { "on", "off"  } do
for _, strategy in helpers.each_strategy() do

describe("lazy_export with #".. strategy .. " inc_sync=" .. inc_sync, function()
  describe("no DP", function ()
    setup(function()
      cp(strategy, inc_sync)
    end)
    teardown(function ()
      helpers.stop_kong()
    end)
    it("test", function ()
      touch_config()
      if inc_sync == "on" then
        assert.logfile().has.no.line("[kong.sync.v2] config push (connected client)", true)

      else
        assert.logfile().has.line("[clustering] skipping config push (no connected clients)", true)
      end
    end)
  end)

  describe("only json DP", function()
    setup(function()
      cp(strategy, inc_sync)
      json_dp(inc_sync)
    end)
    teardown(function ()
      helpers.stop_kong("dp1")
      helpers.stop_kong()
    end)

    it("test", function ()
      touch_config()
      if inc_sync == "on" then
        assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
        assert.logfile().has.line("[kong.sync.v2] database is empty or too far behind for node_id", true)

      else
        assert.logfile().has.line("[clustering] exporting config", true)
        assert.logfile().has.line("[clustering] config pushed to 1 data-plane nodes", true)
      end
    end)
  end)

end)

end -- for _, strategy
end -- for inc_sync