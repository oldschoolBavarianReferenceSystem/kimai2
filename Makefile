NAME = kimai/kimai2
# REPO_SOURCE="https://github.com/kevinpapst/kimai2.git"
TIMEOUT_MAX=10
# NO_CACHE="--no-cache"

# test: update-dev test-dev test-prod

test-dev:
	env NAME=$(NAME) TIMEOUT_MAX=$(TIMEOUT_MAX) bats --tap tests/dev.bats

test-prod:
	env NAME=$(NAME) TIMEOUT_MAX=$(TIMEOUT_MAX) bats --tap tests/prod.bats

build-base:
	docker build -t $(NAME)_base --rm base ${NO_CACHE}

build-dev:
	docker build -t $(NAME):dev --rm dev ${NO_CACHE}
	docker tag $(NAME):dev $(NAME):master ${NO_CACHE}

build-prod:
	docker build -t $(NAME):${TAG} --rm prod ${NO_CACHE}
	docker tag $(NAME):${TAG} $(NAME):prod

build: build-base build-dev build-prod test-dev test-prod

push-dev:
	docker push $(NAME):dev
	docker push $(NAME):master
	docker push $(NAME):latest

push-prod:
	docker push $(NAME):${TAG}
	docker push $(NAME):prod

release-dev: build-base build-dev test-dev push-dev

release-prod: build-base build-prod test-prod push-prod
