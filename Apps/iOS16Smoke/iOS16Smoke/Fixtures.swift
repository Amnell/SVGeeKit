import Foundation

enum Fixtures {
    static let canvas = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 160" width="240" height="160">
      <rect width="240" height="160" fill="#f4f1ea"/>
      <circle cx="80" cy="80" r="42" fill="#e74c3c"/>
      <rect x="128" y="38" width="84" height="84" rx="8" fill="#3498db"/>
      <text x="120" y="148" text-anchor="middle" font-size="14" fill="#2c3e50">iOS 16 canvas</text>
    </svg>
    """

    static let animate = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 80" width="200" height="80">
      <rect x="0" y="0" width="200" height="80" fill="#f4f1ea"/>
      <rect x="10" y="20" width="20" height="40" fill="#27ae60">
        <animate attributeName="width" from="20" to="160" dur="2s" fill="freeze"/>
      </rect>
    </svg>
    """

    static let scriptClick = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
      <script type="text/ecmascript"><![CDATA[
        function onClick() {
          document.getElementById('fail').setAttribute('visibility', 'hidden');
          document.getElementById('pass').setAttribute('visibility', 'visible');
        }
      ]]></script>
      <g id="fail" onclick="onClick()">
        <rect x="10" y="10" width="80" height="80" fill="#e74c3c"/>
      </g>
      <g id="pass" visibility="hidden">
        <rect x="10" y="10" width="80" height="80" fill="#27ae60"/>
      </g>
    </svg>
    """
}
