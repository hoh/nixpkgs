{ lib, pkgs, ... }:

let
  modelName = "smollm2-135m-instruct-q2-k";

  smollm2-135m-instruct-q2-k = pkgs.fetchFromHuggingFace {
    repoId = "Segilmez06/SmolLM2-135M-Instruct-Q2_K-GGUF";
    rev = "c7547743d6946e7be4b87b52e85cf84c942a5f86";
    hash = "sha256-BnsuX8WiFLqgd7IS6NP0z2zXm6lrVHF598jUK0++tLU=";
  };

  package = pkgs.thunderbird-thunderbolt.override {
    bypassWaitlist = true;
    e2eeEnabled = false;
    skipOnboarding = true;
  };

  webRoot = "${package}/share/thunderbird-thunderbolt/dist";

  seleniumScript =
    pkgs.writers.writePython3Bin "thunderbird-thunderbolt-selenium"
      {
        libraries = with pkgs.python3Packages; [ selenium ];
      }
      ''
        import time

        from selenium import webdriver
        from selenium.common.exceptions import TimeoutException
        from selenium.webdriver.common.by import By
        from selenium.webdriver.firefox.options import Options
        from selenium.webdriver.support import expected_conditions as EC
        from selenium.webdriver.support.ui import WebDriverWait


        base_url = "http://127.0.0.1:8081"
        llama_url = "http://127.0.0.1:8080"
        model_name = "${modelName}"

        options = Options()
        options.add_argument("--headless")
        service = webdriver.FirefoxService(executable_path="${lib.getExe pkgs.geckodriver}")  # noqa: E501

        driver = webdriver.Firefox(options=options, service=service)
        driver.implicitly_wait(1)
        wait = WebDriverWait(driver, 60)


        def find(xpath, timeout=60):
            return WebDriverWait(driver, timeout).until(
                EC.presence_of_element_located((By.XPATH, xpath))
            )


        def click(xpath, timeout=60):
            element = WebDriverWait(driver, timeout).until(
                EC.element_to_be_clickable((By.XPATH, xpath))
            )
            driver.execute_script(
                "arguments[0].scrollIntoView({block: 'center', inline: 'center'});",
                element,
            )
            element.click()
            return element


        def input_after_label(label):
            xpath = (
                f"//label[normalize-space()='{label}']"
                "/following::input[1]"
            )
            return WebDriverWait(driver, 30).until(
                EC.element_to_be_clickable(
                    (By.XPATH, xpath)
                )
            )


        def set_input(element, value):
            driver.execute_script(
                """
                const element = arguments[0];
                const value = arguments[1];
                const setter = Object.getOwnPropertyDescriptor(
                  HTMLInputElement.prototype,
                  'value',
                ).set;

                setter.call(element, value);
                element.dispatchEvent(new Event('input', { bubbles: true }));
                element.dispatchEvent(new Event('change', { bubbles: true }));
                """,
                element,
                value,
            )
            WebDriverWait(driver, 5).until(
                lambda _driver: element.get_attribute("value") == value
            )


        def wait_for_model_combobox():
            deadline = time.time() + 60
            last_error = ""
            while time.time() < deadline:
                errors = driver.find_elements(
                    By.XPATH,
                    "//*[contains(normalize-space(), 'Network request failed')"
                    " or contains(normalize-space(), 'Server responded with status')"
                    " or contains(normalize-space(), 'Failed to load models')]",
                )
                visible_errors = [
                    error.text
                    for error in errors
                    if error.is_displayed()
                ]
                if visible_errors:
                    last_error = "; ".join(visible_errors)
                    set_input(input_after_label("URL"), llama_url)

                candidates = driver.find_elements(
                    By.XPATH,
                    "//label[normalize-space()='Model']"
                    "/following::button[@role='combobox'][1]",
                )
                visible = [
                    candidate
                    for candidate in candidates
                    if candidate.is_displayed()
                ]
                if visible:
                    return visible[0]

                time.sleep(0.5)

            raise TimeoutException(
                "Timed out waiting for model combobox. Last error: " + last_error
            )


        try:
            driver.get(base_url + "/settings/models")
            wait.until(
                lambda d: (
                    d.execute_script("return document.readyState") == "complete"
                )
            )
            find("//h1[normalize-space()='Models']")

            click(
                "//h1[normalize-space()='Models']"
                "/following::button[@data-slot='button'][1]"
            )
            find("//*[@role='dialog' and .//*[normalize-space()='Add Model']]")

            click(
                "//label[normalize-space()='Provider']"
                "/following::button[@data-slot='select-trigger'][1]"
            )
            click(
                "//*[@data-slot='select-item'"
                " and .//span[normalize-space()='Custom']]"
            )

            url_input = input_after_label("URL")
            set_input(url_input, llama_url)

            model_combobox = wait_for_model_combobox()
            model_combobox.click()

            search = WebDriverWait(driver, 30).until(
                EC.element_to_be_clickable(
                    (By.CSS_SELECTOR, "[data-slot='command-input']")
                )
            )
            set_input(search, model_name)
            click(
                "//*[@data-slot='command-item'"
                f" and contains(normalize-space(), '{model_name}')]"
            )

            find("//label[normalize-space()='Display Name']/following::input[1]")

            click("//button[normalize-space()='Test Model']")
            find("//*[normalize-space()='Test successful!']", timeout=90)

            click("//button[normalize-space()='Add Model']")
            WebDriverWait(driver, 30).until_not(
                EC.presence_of_element_located((By.XPATH, "//*[@role='dialog']"))
            )
            find(f"//*[contains(normalize-space(), '{model_name}')]")
        except Exception:
            print("Current URL:", driver.current_url)
            try:
                print("URL field:", input_after_label("URL").get_attribute("value"))
            except Exception:
                pass
            print(driver.page_source[:8000])
            raise
        finally:
            driver.quit()
      '';
in
{
  name = "thunderbird-thunderbolt";

  meta.maintainers = with lib.maintainers; [ hoh ];

  nodes.machine =
    { pkgs, ... }:
    {
      virtualisation = {
        cores = 4;
        memorySize = 4096;
      };

      services.llama-cpp = {
        enable = true;
        model = "${smollm2-135m-instruct-q2-k}/smollm2-135m-instruct-q2_k.gguf";
        port = 8080;
        extraFlags = [
          "--alias"
          modelName
          "--no-webui"
          "--no-warmup"
          "-c"
          "256"
          "-n"
          "16"
          "-t"
          "4"
          "-tb"
          "4"
          "--temp"
          "0"
        ];
      };

      services.nginx = {
        enable = true;
        virtualHosts."thunderbird-thunderbolt" = {
          default = true;
          listen = [
            {
              addr = "127.0.0.1";
              port = 8081;
            }
          ];
          root = webRoot;
          extraConfig = ''
            add_header Cross-Origin-Embedder-Policy "require-corp" always;
            add_header Cross-Origin-Opener-Policy "same-origin" always;
          '';
          locations."/" = {
            tryFiles = "$uri $uri/ /index.html";
          };
        };
      };

      environment.systemPackages = [
        pkgs.curl
        pkgs.firefox-unwrapped
        pkgs.geckodriver
        pkgs.jq
        seleniumScript
      ];
    };

  testScript = ''
    import json


    def get_json(command):
        return json.loads(machine.succeed(command))


    machine.wait_for_unit("llama-cpp.service")
    machine.wait_for_open_port(8080)
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(8081)

    with subtest("packaged assets are served with cross-origin isolation headers"):
        machine.succeed("test -x ${package}/bin/thunderbolt")
        machine.succeed("test -f ${webRoot}/index.html")
        machine.succeed(
            "curl -fsSI http://127.0.0.1:8081/settings/models"
            " | grep -Fi 'Cross-Origin-Embedder-Policy: require-corp'"
        )
        machine.succeed(
            "curl -fsSI http://127.0.0.1:8081/settings/models"
            " | grep -Fi 'Cross-Origin-Opener-Policy: same-origin'"
        )

    with subtest("llama-cpp exposes the expected OpenAI-compatible model"):
        models = get_json("curl -fsS http://127.0.0.1:8080/v1/models")
        model_ids = [model["id"] for model in models["data"]]
        assert "${modelName}" in model_ids, model_ids

    with subtest("llama-cpp answers OpenAI-compatible chat completions"):
        response = get_json(
            "curl -fsS -H 'Content-Type: application/json' "
            "-d '{"
            "\"model\":\"${modelName}\","
            "\"messages\":[{\"role\":\"user\",\"content\":\"Say test successful.\"}],"
            "\"max_tokens\":8,"
            "\"temperature\":0"
            "}' "
            "http://127.0.0.1:8080/v1/chat/completions"
        )
        assert response["model"] == "${modelName}", response
        message = response["choices"][0]["message"]
        assert message["role"] == "assistant", response
        assert len(message["content"]) > 0, response

    with subtest("Firefox can add and test the llama-cpp custom model through Thunderbolt"):
        machine.succeed("PYTHONUNBUFFERED=1 thunderbird-thunderbolt-selenium")
  '';
}
