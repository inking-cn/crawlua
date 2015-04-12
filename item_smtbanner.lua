local http = require "socket.http"
local cjson = require "cjson"

run = function (params)
	local data = cjson.decode(params)
	local headers = {}
	if data.is_mobile == "1" then
		headers["User-Agent"] = "Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16"
	else
		headers["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:32.0) Gecko/20100101 Firefox/32.0"
	end
	local t = {}
	local response, code = http.request{url=data.url, headers=headers, sink = ltn12.sink.table(t)}
	local result = {}
	if code == 200 then
		local c = table.concat(t)
		for m in string.gmatch(c, "<div class=\"smtBannerList\">%s*<ul>(.-)</ul>%s*</div>") do
			for href, img in string.gmatch(m, "<li>%s*<a href=[\"\'](.-)[\"\']>%s*<img%s*src=[\"\'](.-)(%?_ex=.*)[\"\']>%s*</a>%s*</li>") do
				table.insert(result, {href = href, img = img})
			end
		end
	end
	return cjson.encode({result = result})
end

print(run('{"is_mobile":"1","url":"http://item.rakuten.co.jp/advancesports/n121018-02"}'))