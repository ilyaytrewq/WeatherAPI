FROM julia:1.11.6-bookworm

WORKDIR /app

COPY Project.toml ./

RUN julia -e 'using Pkg; \
  Pkg.activate("."); \
  Pkg.add(PackageSpec(url="https://github.com/bhftbootcamp/OhMyCH.jl.git")); \
  Pkg.instantiate()'

COPY src ./src

EXPOSE 8080
CMD ["julia", "--project=.", "src/WeatherAPI.jl"]
