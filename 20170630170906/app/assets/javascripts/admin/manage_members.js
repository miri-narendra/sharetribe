window.ST = window.ST || {};

/**
  Maganage members in admin UI
*/
window.ST.initializeManageMembers = function() {
  /*
   * submit changes in checkboxes
   */
  function checkboxToValueObject(element) {
    var r = {};
    r[$(element).val()] = $(element).prop("checked");
    return r;
  }

  function createCheckboxAjaxRequest(selector, url, allowedKey, disallowedKey) {
    var streams = $(selector).toArray().map(function(domElement) {
      return $(domElement).asEventStream("change").map(function(event){
        return checkboxToValueObject(event.target);
      }).toProperty(checkboxToValueObject(domElement));
    });

    var ajaxRequest = Bacon.combineAsArray(streams).changes().debounce(800).skipDuplicates(_.isEqual).map(function(valueObjects) {
      function isValueTrue(valueObject) {
        return _.values(valueObject)[0];
      }

      var allowed = _.filter(valueObjects, isValueTrue);
      var disallowed = _.reject(valueObjects, isValueTrue);

      var data = {};
      data[allowedKey] = _.keys(ST.utils.objectsMerge(allowed));
      data[disallowedKey] = _.keys(ST.utils.objectsMerge(disallowed));

      return {
        type: "POST",
        url: ST.utils.relativeUrl(url),
        data: data
      };
    });

    return ajaxRequest;
  }

  /*
   * submit changes in text inputs
   */
  $.fn.inlineEdit = function() {
      $(this).hover(function() {
          $(this).addClass('hover');
      }, function() {
          $(this).removeClass('hover');
      });

      $(this).click(function() {

          replaceWith = $('<input>');
          replaceWith.attr('type', 'text');
          replaceWith.attr('data-id', $(this).attr('data-id'));
          var elem = $(this);

          elem.hide();
          elem.after(replaceWith);
          replaceWith.focus();

          replaceWith.blur(function() {
              id = $(this).attr('data-id');
              connectWith = $('input[type=hidden][data-id='+id+']');

              if ($(this).val() != "") {
                  connectWith.val($(this).val()).change();
                  elem.text($(this).val());
              }

              $(this).remove();
              elem.show();
          });
      });
  };

  function inputToValueObject(element) {
    var r = {};
    r['id'] = $(element).attr("data-id");
    r['value'] = $(element).val();
    return r;
  }

  function createTextAjaxRequest(selector, url, stream_name){
    //configure inline editor
    $(".inline-editable").inlineEdit();

    //setup ajax requests
    var streams = $(selector).toArray().map(function(domElement) {
      return $(domElement).asEventStream("change").map(function(event){
        return inputToValueObject(event.target);
      }).toProperty(inputToValueObject(domElement));
    });

    var ajaxRequest = Bacon.combineAsArray(streams).changes().debounce(800).skipDuplicates(_.isEqual).map(function(valueObjects) {
      var data = {};
      data[stream_name] = _.object(_.map(valueObjects, function(item){
                            return [item['id'], item['value']]
                          }));

      return {
        type: "POST",
        url: ST.utils.relativeUrl(url),
        data: data
      };
    });

    return ajaxRequest;
  }

  /*
   * preparing ajax requests
   */
  var postingAllowed = createCheckboxAjaxRequest(".admin-members-can-post-listings", "posting_allowed", "allowed_to_post", "disallowed_to_post");
  var isAdmin = createCheckboxAjaxRequest(".admin-members-is-admin", "promote_admin", "add_admin", "remove_admin");
  var isOwner = createCheckboxAjaxRequest(".admin-members-is-owner", "promote_to_owner", "add_owner", "remove_owner");
  var allowInquiry = createCheckboxAjaxRequest(".admin-members-allow-inquiry", "promote_to_allow_inquiry", "allow_inquiry", "do_not_allow_inquiry");
  var setCommissionPercent = createTextAjaxRequest(".admin-members-commission-percent", "set_commission_percent", 'commission_percent');

  var ajaxRequest = postingAllowed.merge(isAdmin).merge(isOwner).merge(allowInquiry);
  var ajaxRequest = ajaxRequest.merge(setCommissionPercent);
  var ajaxResponse = ajaxRequest.ajax().endOnError();

  /*
   * showing ajax request status
   */
  var ajaxStatus = window.ST.ajaxStatusIndicator(ajaxRequest, ajaxResponse);

  ajaxStatus.loading.onValue(function() {
    $(".ajax-update-notification").show();
    $("#admin-members-saving-posting-allowed").show();
    $("#admin-members-error-posting-allowed").hide();
    $("#admin-members-saved-posting-allowed").hide();
  });

  ajaxStatus.success.onValue(function() {
    $("#admin-members-saving-posting-allowed").hide();
    $("#admin-members-saved-posting-allowed").show();
  });

  ajaxStatus.error.onValue(function() {
    $("#admin-members-saving-posting-allowed").hide();
    $("#admin-members-error-posting-allowed").show();
  });

  ajaxStatus.idle.onValue(function() {
    $(".ajax-update-notification").fadeOut();
  });

  // Attach analytics click handler for CSV export
  $(".js-users-csv-export").click(function(){
    /* global report_analytics_event */
    report_analytics_event('admin', 'export', 'users');
  });

};
