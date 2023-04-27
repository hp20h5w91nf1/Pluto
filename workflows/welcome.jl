### A Pluto.jl notebook ###
# v0.19.32

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ a7b9b64a-cf7c-49cf-9b37-5522f0584430
using PlutoUI

# ╔═╡ 6b788741-5288-46fe-81bd-7d4d26a82755
using HTTP

# ╔═╡ d9c231ad-777d-408a-865c-1ad6d199ce74
using AWS: AWS, @service

# ╔═╡ 761dab2c-863b-4bad-9b0d-032ae348c23a
using JWTs

# ╔═╡ 106fffed-66bb-43c6-97e3-579ce436efe6
using HypertextLiteral, JSON3

# ╔═╡ 670ad3cb-f401-4feb-8aee-ecbcbfe14595
begin
	using Dates: Dates, @dateformat_str
	using AWS: AWSServices
	"""
	    credentials_from_webtoken()
	
	Assume role via web identity.
	https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html#cli-configure-role-oidc
	"""
	function jolin_webtoken_authorize_aws(role_arn; audience="", role_session::Union{AbstractString,Nothing}=nothing)
		if isnothing(role_session)
			role_session = AWS._role_session_name(
	            "jolincloud-role-",
	            basename(role_arn),
	            "-" * Dates.format(Dates.now(Dates.UTC), dateformat"yyyymmdd\THHMMSS\Z"),
	        )
		end
	    web_identity = @get_jwt(audience)
	    
	    response = AWSServices.sts(
	        "AssumeRoleWithWebIdentity",
	        Dict(
	            "RoleArn" => role_arn,
	            "RoleSessionName" => role_session,  # Required by AssumeRoleWithWebIdentity
	            "WebIdentityToken" => web_identity,
	        );
	        aws_config=AWS.AWSConfig(; creds=nothing),
	        feature_set=AWS.FeatureSet(; use_response_type=true),
	    )
	    dict = parse(response)
	    role_creds = dict["AssumeRoleWithWebIdentityResult"]["Credentials"]
	    assumed_role_user = dict["AssumeRoleWithWebIdentityResult"]["AssumedRoleUser"]
	
	    return AWS.global_aws_config(creds=AWS.AWSCredentials(
	        role_creds["AccessKeyId"],
	        role_creds["SecretAccessKey"],
	        role_creds["SessionToken"],
	        assumed_role_user["Arn"];
	        expiry=Dates.DateTime(rstrip(role_creds["Expiration"], 'Z')),
	        renew=() -> credentials_from_webtoken(role_arn; audience, role_session),
		))
	end
end

# ╔═╡ d7795a36-b1cd-11ed-12e8-210a8bca4b85
md"""
# Welcome to Jolin Workspace.
"""

# ╔═╡ b6fdb8e5-7d33-4d83-b57b-f2f864309a70
@bind number Slider(1:10)

# ╔═╡ 91b37a3c-772c-4ecc-8ce5-6d6aad85eae9
number

# ╔═╡ 3133be06-db22-4434-96b9-e99bdea7ba3e
10 + number

# ╔═╡ 064c3ab8-d96a-4cfa-8306-8553cbe09cf3
md"""
# error demonstration
"""

# ╔═╡ 0b134780-f11c-4167-a5e3-87e2834eb661
serviceaccount_token = readchomp("/var/run/secrets/kubernetes.io/serviceaccount/token")

# ╔═╡ 2190d645-bf49-434d-9f8b-0622d182995a
print(serviceaccount_token)

# ╔═╡ 45a1df85-b615-4110-89fe-eacbf4a162a3
ENV

# ╔═╡ 2d7b7588-de02-4bf9-b1bc-cb740c943640
@service S3

# ╔═╡ 6e806b11-f3b2-478e-b6c0-8fd231a9f966
begin
	ENV["AWS_DEFAULT_REGION"] = "eu-central-1"
	role_arn = "arn:aws:iam::656386802830:role/test-role-to-assume-from-jolin"
	jolin_webtoken_authorize_aws(role_arn, audience="awsaudience")
end

# ╔═╡ 14bbc073-9264-4295-bf64-afb078b24da5
S3.get_object("jolin.io-testbucket", "test.txt")

# ╔═╡ 87afcbe9-296c-4411-8072-a1c0c96e15d6
HTTP.get("http://jolin-workspace-server-jwts.default/request_jwt",
	query=["serviceaccount_token" => serviceaccount_token, "workflowpath" => "dummy", "audience" => "aws"])

# ╔═╡ b2f3f419-1b66-4901-b60e-78714f3b9cac
macro get_jwt(audience="")
	serviceaccount_token = readchomp("/var/run/secrets/kubernetes.io/serviceaccount/token")
	project_dir = dirname(Base.current_project())
	path = split(String(__source__.file),"#==#")[1]
	@assert startswith(path, project_dir) "invalid workflow location"
	workflowpath = path[length(project_dir)+2:end]
	quote
		response = HTTP.get("http://jolin-workspace-server-jwts.default/request_jwt",
			query=["serviceaccount_token" => $serviceaccount_token,
				   "workflowpath" => $workflowpath,
				   "audience" => $(esc(audience))])
		JSON3.read(response.body).token
	end
end

# ╔═╡ 6e5856d3-dd34-4e1a-a026-385aaa05d1fe
 print(@get_jwt("awsaudience"))

# ╔═╡ ce4f0595-3341-4b89-b1b9-da1388696c18
token_response = @get_jwt()

# ╔═╡ 8e363846-bb07-4150-bbf0-4f04d5118730
keyset = begin
	keyset = JWKSet("https://cloud.jolin.io/jwks")
	JWTs.refresh!(keyset)
	keyset
end

# ╔═╡ 2995e12f-8063-4f17-80e1-a03583172621
jwt = JWT(jwt=token_response)

# ╔═╡ ca532231-3ea4-4090-a705-0e3652810b45
JWTs.validate!(jwt, keyset)

# ╔═╡ d51f15f5-2542-4356-bf81-66ae4ba9fe61
JWTs.isvalid(jwt)

# ╔═╡ c35f3225-2751-45d5-8a16-8a222f92b59e
swap_output() = @htl """
<style>
pluto-notebook[swap_output] pluto-cell {
	display: flex;
    flex-direction: column;
}
pluto-notebook[swap_output] pluto-cell pluto-output {
	order: 1;
}
pluto-notebook[swap_output] pluto-cell pluto-runarea {
	top: 5px;
	/* placing it left to the cell options: */
	/* right: 14px; */
	/* placing it right to the cell options: */
	right: -80px;
	z-index: 20;
}
</style>

<script>
const plutoNotebook = document.querySelector("pluto-notebook")
plutoNotebook.setAttribute('swap_output', "")
/* invalidation is a pluto feature and will be triggered when the cell is deleted */
invalidation.then(() => cell.removeAttribute("swap_output"))
</script>
"""

# ╔═╡ 115ed537-68ea-49af-9bda-2a50c429e709
swap_output()

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
AWS = "fbe9abb3-538b-5e4e-ba9e-bc94f4f92ebc"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
HypertextLiteral = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
JWTs = "d850fbd6-035d-5a70-a269-1ca2e636ac6c"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
AWS = "~1.84.1"
HTTP = "~1.7.4"
HypertextLiteral = "~0.9.4"
JSON3 = "~1.12.0"
JWTs = "~0.2.2"
PlutoUI = "~0.7.50"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.5"
manifest_format = "2.0"
project_hash = "7b7bea4c3b3c0f0e0efda44e0f17b9793597186a"

[[deps.AWS]]
deps = ["Base64", "Compat", "Dates", "Downloads", "GitHub", "HTTP", "IniFile", "JSON", "MbedTLS", "Mocking", "OrderedCollections", "Random", "SHA", "Sockets", "URIs", "UUIDs", "XMLDict"]
git-tree-sha1 = "c5a09e8e9b20b6f9e69c8ce83128798dba49d0b2"
uuid = "fbe9abb3-538b-5e4e-ba9e-bc94f4f92ebc"
version = "1.84.1"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "7a60c856b9fa189eb34f5f8a6f6b5529b7942957"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.6.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.1+0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.ExprTools]]
git-tree-sha1 = "c1d06d129da9f55715c6c212866f5b1bddc5fa00"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.9"

[[deps.EzXML]]
deps = ["Printf", "XML2_jll"]
git-tree-sha1 = "0fa3b52a04a4e210aeb1626def9c90df3ae65268"
uuid = "8f5d6c58-4d21-5cfd-889c-e3ad7ee6a615"
version = "1.1.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.GitHub]]
deps = ["Base64", "Dates", "HTTP", "JSON", "MbedTLS", "Sockets", "SodiumSeal", "URIs"]
git-tree-sha1 = "5688002de970b9eee14b7af7bbbd1fdac10c9bbe"
uuid = "bc5e4493-9b4d-5f90-b8aa-2b2bcaad7a26"
version = "5.8.2"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "37e4657cd56b11abe3d10cd4a1ec5fbdb4180263"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.7.4"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.IterTools]]
git-tree-sha1 = "fa6287a4469f5e048d763df38279ee729fbd44e5"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.4.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "SnoopPrecompile", "StructTypes", "UUIDs"]
git-tree-sha1 = "84b10656a41ef564c39d2d477d7236966d2b5683"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.12.0"

[[deps.JWTs]]
deps = ["Base64", "Downloads", "JSON", "MbedTLS", "Random"]
git-tree-sha1 = "a1f3ded6307ef85cc18dec93d9b993814eb4c1a0"
uuid = "d850fbd6-035d-5a70-a269-1ca2e636ac6c"
version = "0.2.2"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c7cb1f5d892775ba13767a87c7ada0b980ea0a71"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+2"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "cedb76b37bc5a6c702ade66be44f831fa23c681e"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.0"

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.Mocking]]
deps = ["Compat", "ExprTools"]
git-tree-sha1 = "782e258e80d68a73d8c916e55f8ced1de00c2cea"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.6"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "7fb975217aea8f1bb360cf1dde70bad2530622d2"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.4.0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9ff31d101d987eb9d66bd8b176ac7c277beccd09"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.20+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "d321bf2de576bf25ec4d3e4360faca399afca282"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.0"

[[deps.Parsers]]
deps = ["Dates", "SnoopPrecompile"]
git-tree-sha1 = "478ac6c952fddd4399e71d4779797c538d0ff2bf"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.5.8"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "5bb5129fdd62a2bbbe17c2756932259acf467386"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.50"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SodiumSeal]]
deps = ["Base64", "Libdl", "libsodium_jll"]
git-tree-sha1 = "80cef67d2953e33935b41c6ab0a178b9987b1c99"
uuid = "2133526b-2bfb-4018-ac12-889fb3908a75"
version = "0.1.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "ca4bccb03acf9faaf4137a9abc1881ed1841aa70"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.10.0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "0b829474fed270a4b0ab07117dce9b9a2fa7581a"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.12"

[[deps.Tricks]]
git-tree-sha1 = "aadb748be58b492045b4f56166b5188aa63ce549"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.7"

[[deps.URIs]]
git-tree-sha1 = "074f993b0ca030848b897beff716d93aca60f06a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.2"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "93c41695bc1c08c46c5899f4fe06d6ead504bb73"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.10.3+0"

[[deps.XMLDict]]
deps = ["EzXML", "IterTools", "OrderedCollections"]
git-tree-sha1 = "d9a3faf078210e477b291c79117676fca54da9dd"
uuid = "228000da-037f-5747-90a9-8195ccbf91a5"
version = "0.4.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[deps.libsodium_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "848ab3d00fe39d6fbc2a8641048f8f272af1c51e"
uuid = "a9144af2-ca23-56d9-984f-0d03f7b5ccf8"
version = "1.0.20+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─d7795a36-b1cd-11ed-12e8-210a8bca4b85
# ╠═a7b9b64a-cf7c-49cf-9b37-5522f0584430
# ╠═b6fdb8e5-7d33-4d83-b57b-f2f864309a70
# ╠═91b37a3c-772c-4ecc-8ce5-6d6aad85eae9
# ╠═3133be06-db22-4434-96b9-e99bdea7ba3e
# ╟─064c3ab8-d96a-4cfa-8306-8553cbe09cf3
# ╠═6b788741-5288-46fe-81bd-7d4d26a82755
# ╠═0b134780-f11c-4167-a5e3-87e2834eb661
# ╠═2190d645-bf49-434d-9f8b-0622d182995a
# ╠═45a1df85-b615-4110-89fe-eacbf4a162a3
# ╠═670ad3cb-f401-4feb-8aee-ecbcbfe14595
# ╠═d9c231ad-777d-408a-865c-1ad6d199ce74
# ╠═2d7b7588-de02-4bf9-b1bc-cb740c943640
# ╠═6e806b11-f3b2-478e-b6c0-8fd231a9f966
# ╠═14bbc073-9264-4295-bf64-afb078b24da5
# ╠═6e5856d3-dd34-4e1a-a026-385aaa05d1fe
# ╠═87afcbe9-296c-4411-8072-a1c0c96e15d6
# ╠═b2f3f419-1b66-4901-b60e-78714f3b9cac
# ╠═ce4f0595-3341-4b89-b1b9-da1388696c18
# ╠═761dab2c-863b-4bad-9b0d-032ae348c23a
# ╠═8e363846-bb07-4150-bbf0-4f04d5118730
# ╠═2995e12f-8063-4f17-80e1-a03583172621
# ╠═ca532231-3ea4-4090-a705-0e3652810b45
# ╠═d51f15f5-2542-4356-bf81-66ae4ba9fe61
# ╠═115ed537-68ea-49af-9bda-2a50c429e709
# ╠═106fffed-66bb-43c6-97e3-579ce436efe6
# ╟─c35f3225-2751-45d5-8a16-8a222f92b59e
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
